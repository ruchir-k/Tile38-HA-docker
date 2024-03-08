FROM tile38/tile38:latest

WORKDIR /data
COPY ./config /data/
EXPOSE 9851
CMD [ "tile38-server", "-d", "/data", "--appendonly", "yes","-vv" ]
RUN echo "Running master......"
