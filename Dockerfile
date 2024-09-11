FROM openresty/openresty:alpine-fat

# allowed domains should be lua match pattern
ENV DIFFIE_HELLMAN='' \
    ALLOWED_DOMAINS='.*' \
    AUTO_SSL_VERSION='0.13.1' \
    FORCE_HTTPS='true' \
    SITES='' \
    LETSENCRYPT_URL='https://acme-v02.api.letsencrypt.org/directory' \
    STORAGE_ADAPTER='file' \
    REDIS_HOST='' \
    REDIS_PORT='6379' \
    REDIS_DB='0' \
    REDIS_KEY_PREFIX='' \
    RESOLVER_ADDRESS='8.8.8.8'

# Install dependencies for ModSecurity
RUN apk --no-cache add bash openssl git build-base autoconf automake libtool \
    pcre-dev zlib-dev yajl-dev lmdb-dev libxml2-dev geoip-dev curl-dev libmaxminddb-dev linux-headers flex doxygen cmake

# Install lua-resty-auto-ssl for handling SSL certificates and ModSecurity
RUN /usr/local/openresty/luajit/bin/luarocks install lua-resty-auto-ssl $AUTO_SSL_VERSION \
    && openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj '/CN=sni-support-required-for-valid-ssl' \
        -keyout /etc/ssl/resty-auto-ssl-fallback.key \
        -out /etc/ssl/resty-auto-ssl-fallback.crt \
    && openssl dhparam -out /usr/local/openresty/nginx/conf/dhparam.pem 2048 \
    && rm /etc/nginx/conf.d/default.conf

# Clone and build ModSecurity v3
RUN git clone --depth 1 -b v3/master https://github.com/owasp-modsecurity/ModSecurity /opt/ModSecurity && \
    cd /opt/ModSecurity && \
    git submodule init && \
    git submodule update && \
    ./build.sh && \
    ./configure && \
    make && \
    make install

# Clone and build the ModSecurity NGINX connector
# Version must match version of NGINX used by OpenResty
RUN git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git /opt/ModSecurity-nginx && \
    cd /opt/ModSecurity-nginx && \
    curl -LO http://nginx.org/download/nginx-1.25.3.tar.gz && \
    tar -zxvf nginx-1.25.3.tar.gz && \
    cd nginx-1.25.3 && \
    ./configure --with-compat --add-dynamic-module=/opt/ModSecurity-nginx && \
    make modules && \
    cp objs/ngx_http_modsecurity_module.so /usr/local/openresty/nginx/modules/

# Clone OWASP ModSecurity CRS
RUN git clone --depth 1 https://github.com/coreruleset/coreruleset.git /etc/nginx/owasp-modsecurity-crs

# Copy the ModSecurity default config and OWASP Core Rule Set (CRS)
COPY modsecurity.conf /etc/nginx/modsecurity.conf

# Copy the NGINX configuration and entrypoint
COPY nginx.conf snippets /usr/local/openresty/nginx/conf/
COPY entrypoint.sh /entrypoint.sh

# Volume for AutoSSL
VOLUME /etc/resty-auto-ssl

# Expose necessary ports
EXPOSE 80 443

# Entry point for the container
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
