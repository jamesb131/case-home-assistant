FROM postgres:15-alpine

RUN apk add --no-cache jq

ENV PGDATA=/data/postgres

COPY deploy/ha/case-postgres/run.sh /usr/local/bin/case-postgres-run.sh
RUN chmod +x /usr/local/bin/case-postgres-run.sh

EXPOSE 5432

ENTRYPOINT ["/usr/local/bin/case-postgres-run.sh"]
CMD ["postgres"]
