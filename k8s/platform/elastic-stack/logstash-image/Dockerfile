FROM docker.elastic.co/logstash/logstash:8.17.0

USER root

COPY aws-msk-iam-auth-all.jar /usr/share/logstash/vendor/aws-msk-iam-auth-all.jar
COPY logstash.conf /usr/share/logstash/pipeline/logstash.conf

RUN chown logstash:root /usr/share/logstash/vendor/aws-msk-iam-auth-all.jar
RUN chown logstash:root /usr/share/logstash/pipeline/logstash.conf

USER logstash
