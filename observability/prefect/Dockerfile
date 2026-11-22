
FROM prefecthq/prefect:3.1.15-python3.12

USER root

RUN useradd --create-home --uid 10001 aegisvolt \
    && mkdir -p /opt/aegisvolt/prefect \
    && mkdir -p /usr/local/lib/python3.12/site-packages/prefect/server/ui_build \
    && chown -R 10001:10001 /opt/aegisvolt \
    && chown -R 10001:10001 /usr/local/lib/python3.12/site-packages/prefect/server/ui_build


COPY requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir --only-binary=:all: \
    -r /tmp/requirements.txt

ENV HOME=/home/aegisvolt
ENV PREFECT_HOME=/home/aegisvolt/.prefect

USER 10001
