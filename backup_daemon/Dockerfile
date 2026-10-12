FROM debian:12.15-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-client \
    restic \
    cron \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY backup.sh .
RUN chmod +x backup.sh

COPY restore.sh .
RUN chmod +x restore.sh

COPY crontab /etc/cron.d/backup-arches
RUN chmod 0644 /etc/cron.d/backup-arches && crontab /etc/cron.d/backup-arches

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]

CMD ["cron", "-f"]