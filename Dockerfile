FROM tugboatqa/php:7.2.16-fpm-stretch

ENV NGINX_VERSION 1.15.4-1~stretch
ENV NJS_VERSION   1.15.4.0.2.4-1~stretch

RUN set -xe && \
  apt-get update && \
  apt-get install --no-install-recommends --no-install-suggests -y gnupg1 apt-transport-https ca-certificates && \
  curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
  echo "deb http://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
  apt-get update && \
  curl -fsSL https://nginx.org/keys/nginx_signing.key | sudo apt-key add - && \
  dpkgArch="$(dpkg --print-architecture)" \
	&& nginxPackages=" \
		nginx=${NGINX_VERSION} \
		nginx-module-xslt=${NGINX_VERSION} \
		nginx-module-geoip=${NGINX_VERSION} \
		nginx-module-image-filter=${NGINX_VERSION} \
		nginx-module-njs=${NJS_VERSION} \
	" \
	&& case "$dpkgArch" in \
		amd64|i386) \
# arches officialy built by upstream
			echo "deb https://nginx.org/packages/mainline/debian/ stretch nginx" >> /etc/apt/sources.list.d/nginx.list \
			&& apt-get update \
			;; \
		*) \
# we're on an architecture upstream doesn't officially build for
# let's build binaries from the published source packages
			echo "deb-src https://nginx.org/packages/mainline/debian/ stretch nginx" >> /etc/apt/sources.list.d/nginx.list \
			\
# new directory for storing sources and .deb files
			&& tempDir="$(mktemp -d)" \
			&& chmod 777 "$tempDir" \
# (777 to ensure APT's "_apt" user can access it too)
			\
# save list of currently-installed packages so build dependencies can be cleanly removed later
			&& savedAptMark="$(apt-mark showmanual)" \
			\
# build .deb files from upstream's source packages (which are verified by apt-get)
			&& apt-get update \
			&& apt-get build-dep -y $nginxPackages \
			&& ( \
				cd "$tempDir" \
				&& DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
					apt-get source --compile $nginxPackages \
			) \
# we don't remove APT lists here because they get re-downloaded and removed later
			\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
# (which is done after we install the built packages so we don't have to redownload any overlapping dependencies)
			&& apt-mark showmanual | xargs apt-mark auto > /dev/null \
			&& { [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; } \
			\
# create a temporary local APT repo to install from (so that dependency resolution can be handled by APT, as it should be)
			&& ls -lAFh "$tempDir" \
			&& ( cd "$tempDir" && dpkg-scanpackages . > Packages ) \
			&& grep '^Package: ' "$tempDir/Packages" \
			&& echo "deb [ trusted=yes ] file://$tempDir ./" > /etc/apt/sources.list.d/temp.list \
# work around the following APT issue by using "Acquire::GzipIndexes=false" (overriding "/etc/apt/apt.conf.d/docker-gzip-indexes")
#   Could not open file /var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages - open (13: Permission denied)
#   ...
#   E: Failed to fetch store:/var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages  Could not open file /var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages - open (13: Permission denied)
			&& apt-get -o Acquire::GzipIndexes=false update \
			;; \
	esac \
	\
	&& apt-get install --no-install-recommends --no-install-suggests -y \
						$nginxPackages \
						gettext-base \
	&& apt-get remove --purge --auto-remove -y apt-transport-https ca-certificates && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/nginx.list \
	\
# if we have leftovers from building, let's purge them (including extra, unnecessary build deps)
	&& if [ -n "$tempDir" ]; then \
		apt-get purge -y --auto-remove \
		&& rm -rf "$tempDir" /etc/apt/sources.list.d/temp.list; \
	fi

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

# Install aws cli tools.
RUN set -xe && \
    apt-get update && apt-get install -y python-pip groff && \
    pip install awscli --upgrade && \
    apt-get clean all && \
    apt-get purge -y --auto-remove

# Install required php extensions.
RUN set -xe && \
    cd /usr/src && \
    apt-get update && \
    apt-get install -y libxml2 libxml2-dev libpng16-16 libpng-dev libjpeg62-turbo libjpeg62-turbo-dev && \
    docker-php-source extract && \
    /usr/local/bin/docker-php-ext-install mysqli && \
    /usr/local/bin/docker-php-ext-install gd && \
    /usr/local/bin/docker-php-ext-install soap && \
    /usr/local/bin/docker-php-ext-install zip && \
    /usr/local/bin/docker-php-ext-install simplexml && \

    /usr/local/bin/docker-php-ext-enable mysqli gd soap zip simplexml && \
    apt-get remove -y libxml2-dev libjpeg62-turbo-dev libpng-dev && \
    docker-php-source delete && \
    apt-get clean all

RUN set -xe && \
    mkdir -p /etc/service/nginx

COPY services/nginx/run /etc/service/nginx/run

RUN set -xe && \
    mkdir -p /usr/local/bin

COPY clone-repo-in-sync.sh /usr/local/bin

RUN set -xe && \
    chmod a+x /usr/local/bin/clone-repo-in-sync.sh

RUN set -xe && \
    chmod a+x /etc/service/nginx/run && \
    chmod a+x /etc/service/php/run

RUN set -xe && \
    cd /tmp && \
    mkdir -p composer && \
    cd composer && \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
    EXPECTED_SIGNATURE="$(wget -q -O - https://composer.github.io/installer.sig)" \
    ACTUAL_SIGNATURE="$(php -r "echo hash_file('sha384', 'composer-setup.php');")" \
    test "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" && >&2 echo 'ERROR: Invalid installer signature' && rm composer-setup.php && exit 1; \
    php composer-setup.php --quiet \
    RESULT=$? \
    rm composer-setup.php && \
    cd / && \
    rm -rf /tmp/composer && \
    apt-get clean all

# Install deps required to run the site.
RUN set -xe && \
    apt install -y jq libpng-dev apt-transport-https python-pip jq groff yarn

RUN set -xe && \
    pip install awscli --upgrade

# Install the apt ssl transport.
# Set up deb repo for yarn.
# Update the apt repo again with ssl enabled.
RUN set -xe && \
  apt-get update && \
  apt-get install -y apt-transport-https && \
  curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
  echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
  apt-get update && \
  curl https://raw.githubusercontent.com/creationix/nvm/v0.24.0/install.sh | bash && \
  . /root/.bashrc && \
  echo "Installing node v8.12.0" && \
  nvm install v8.12.0 && \
  echo "Installing yarn." && \
  apt install -y yarn --no-install-recommends && \
  echo "Installing Gulp." && \
  yarn global add gulp && \
  echo "Installing gulp-cli." && \
  yarn global add gulp-cli && \
  echo "Installing bower." && \
  yarn global add bower

COPY tugboat-tools /usr/local

RUN set -xe && \
    cd /usr/local && \
    git clone https://github.com/pixelcat/aws-register-host.git

# Clean up local apt repo.
RUN set -xe && \
    apt-get clean all

EXPOSE 80

STOPSIGNAL SIGTERM

HEALTHCHECK CMD /bin/nc -z 127.0.0.1 80
