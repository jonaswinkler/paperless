FROM ubuntu:20.04 AS jbig2enc

WORKDIR /usr/src/jbig2enc

RUN apt-get update && apt-get install -y --no-install-recommends build-essential automake libtool libleptonica-dev zlib1g-dev git ca-certificates

RUN git clone https://github.com/agl/jbig2enc .
RUN ./autogen.sh
RUN ./configure && make


FROM node:15 AS frontend

WORKDIR /usr/src/paperless/src-ui/

COPY src-ui/package* ./
RUN npm install

COPY src-ui .
RUN node_modules/.bin/ng build --prod --output-hashing none --sourceMap=false

FROM ubuntu:20.04

WORKDIR /usr/src/paperless/

COPY Pipfile* ./

#Dependencies
RUN apt-get update \
  && DEBIAN_FRONTEND="noninteractive" apt-get -y --no-install-recommends install \
		build-essential \
		curl \
		file \
		fonts-liberation \
		gettext \
		ghostscript \
		gnupg \
		icc-profiles-free \
		imagemagick \
		libatlas-base-dev \
		libffi-dev \
		liblept5 \
		libmagic-dev \
		libpoppler-cpp-dev \
		libpq-dev \
		libqpdf-dev \
		libssl-dev \
		libxml2 \
		libxslt1-dev \
		mime-support \
		optipng \
		pngquant \
		python3 \
		python3-pip \
		python3-dev \
		qpdf \
		sudo \
		tesseract-ocr \
		tesseract-ocr-eng \
		tesseract-ocr-deu \
		tesseract-ocr-fra \
		tesseract-ocr-ita \
		tesseract-ocr-spa \
		tzdata \
		unpaper \
		zlib1g \

  && pip3 install --upgrade supervisor pipenv setuptools \
  && pipenv lock -r > requirements.txt \
  && pip3 install -r requirements.txt \
  && pipenv --clear \
  && pip3 uninstall -y pipenv \
	&& apt-get -y purge build-essential libqpdf-dev python3-dev python3-pip \
	&& apt-get -y autoremove --purge \
	&& rm -rf /var/lib/apt/lists/* \
	&& mkdir /var/log/supervisord /var/run/supervisord

# copy scripts
# this fixes issues with imagemagick and PDF
COPY docker/imagemagick-policy.xml /etc/ImageMagick-6/policy.xml
COPY docker/gunicorn.conf.py ./
COPY docker/supervisord.conf /etc/supervisord.conf
COPY docker/docker-entrypoint.sh /sbin/docker-entrypoint.sh

# copy jbig2enc
COPY --from=jbig2enc /usr/src/jbig2enc/src/.libs/libjbig2enc* /usr/local/lib/
COPY --from=jbig2enc /usr/src/jbig2enc/src/jbig2 /usr/local/bin/
COPY --from=jbig2enc /usr/src/jbig2enc/src/*.h /usr/local/include/


# copy app
COPY src/ ./src/
COPY --from=frontend /usr/src/paperless/src-ui/dist/paperless-ui/ /usr/src/paperless/src/documents/static/frontend/

# add users, setup scripts
RUN addgroup --gid 1000 paperless \
	&& useradd --uid 1000 --gid paperless --home-dir /usr/src/paperless paperless \
	&& chown -R paperless:paperless . \
	&& chmod 755 /sbin/docker-entrypoint.sh

WORKDIR /usr/src/paperless/src/

RUN sudo -HEu paperless python3 manage.py collectstatic --clear --no-input

RUN sudo -HEu paperless python3 manage.py compilemessages

VOLUME ["/usr/src/paperless/data", "/usr/src/paperless/media", "/usr/src/paperless/consume", "/usr/src/paperless/export"]
ENTRYPOINT ["/sbin/docker-entrypoint.sh"]
EXPOSE 8000
CMD ["/usr/local/bin/supervisord", "-c", "/etc/supervisord.conf"]

LABEL maintainer="Jonas Winkler <dev@jpwinkler.de>"
