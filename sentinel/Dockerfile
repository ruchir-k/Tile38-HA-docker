FROM redis:7.0

ADD sentinel.conf /data/sentinel.conf
USER root
COPY sentinel-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/sentinel-entrypoint.sh
ENTRYPOINT ["sentinel-entrypoint.sh"]
CMD [ "redis-sentinel", "/data/sentinel.conf" ]
