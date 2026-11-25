# Read-only Nest Wifi exporter: stdlib only, no pip deps.
FROM python:3.12-slim

WORKDIR /app
COPY exporter.py .

# runs as root inside the container only so the loop detector can open an
# AF_PACKET raw socket (needs CAP_NET_RAW); it never writes anywhere
EXPOSE 9668

CMD ["python", "-u", "exporter.py"]
