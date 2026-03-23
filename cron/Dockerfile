FROM alpine:3.16

RUN apk update && \
    apk add --no-cache bash docker-cli docker-cli-compose dos2unix tzdata sudo

COPY cron/backup_arches.sh /usr/local/bin/backup_arches
RUN chmod +x /usr/local/bin/backup_arches

# minuta godzina dzień miesiąca miesiąc dzień tygodnia => sobota o 2:00 AM
RUN echo "0 2 * * 0 /usr/local/bin/backup_arches >> /var/log/backup.log 2>&1" \
    > /etc/crontabs/root

WORKDIR /workdir

CMD ["crond", "-f", "-l", "0"]