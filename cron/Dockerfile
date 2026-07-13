FROM alpine:3.16

RUN apk update && \
    apk add --no-cache bash docker-cli docker-cli-compose dos2unix tzdata sudo

COPY cron/backup_arches.sh /usr/local/bin/backup_arches
RUN chmod +x /usr/local/bin/backup_arches

# minute hour day month day_of_week => 01 day of month at 2:00
RUN echo "0 2 1 * * * /usr/local/bin/backup_arches >> /var/log/backup.log 2>&1" > /etc/crontabs/root

WORKDIR /workdir

CMD ["crond", "-f", "-l", "0"]