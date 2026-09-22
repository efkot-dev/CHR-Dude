FROM alpine:3.24

# Ставим qemu, утилиты для сети (ip link/bridge) и bash (нужен для start.sh)
RUN apk add --no-cache qemu-system-x86_64

RUN mkdir -p /diskimage

# Копируем ваш образ (предварительно разархивируем его в workflow)
COPY chr-7.19.6.img /diskimage/chr.img

# Копируем скрипт запуска
COPY start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
