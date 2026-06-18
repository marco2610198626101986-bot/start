# Установка Jitsi Meet на Armbian

Руководство и скрипт для развёртывания [Jitsi Meet](https://jitsi.org/) на одноплатниках с [Armbian](https://www.armbian.com/) (Orange Pi, RockPro64, Odroid, Raspberry Pi и др.).

## Требования

| Параметр | Минимум | Рекомендуется |
|----------|---------|---------------|
| Armbian | Debian 11+ / Ubuntu 22.04+ | Bookworm / Noble |
| Архитектура | **arm64 (aarch64)** | arm64 |
| RAM | 2 GB | 4 GB+ |
| Диск | 8 GB | 16 GB+ SSD |
| Домен | Обязателен для Let's Encrypt | `meet.example.org` |

> **armhf (32-bit):** официальные пакеты Jitsi рассчитаны на amd64/arm64. На 32-bit ARM установка возможна, но потребует ручной сборки нативных библиотек — не рекомендуется.

## Подготовка

### 1. DNS

Создайте A-запись, указывающую на публичный IP сервера:

```
meet.example.org  →  x.x.x.x
```

### 2. Проброс портов на роутере

| Порт | Протокол | Назначение |
|------|----------|------------|
| 80 | TCP | Let's Encrypt, редирект на HTTPS |
| 443 | TCP | Веб-интерфейс Jitsi |
| 10000 | UDP | Аудио/видео (WebRTC) |
| 3478 | UDP | STUN (опционально) |
| 5349 | TCP | TURN fallback |

### 3. Обновление системы

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

## Быстрая установка (скрипт)

```bash
git clone <this-repo-url> jitsi-armbian
cd jitsi-armbian
chmod +x scripts/install-jitsi-armbian.sh

# Базовая установка
sudo ./scripts/install-jitsi-armbian.sh --domain meet.example.org

# Для одноплатника за NAT с <= 4 GB RAM
sudo ./scripts/install-jitsi-armbian.sh \
  --domain meet.example.org \
  --disable-zram \
  --nat
```

Скрипт выполняет:

- отключение zram (по флагу `--disable-zram`);
- установку OpenJDK 17, nginx, Prosody и Jitsi Meet;
- настройку firewall (ufw);
- выпуск сертификата Let's Encrypt;
- сборку `libjnisctp` для ARM64 (если в пакете нет готовой библиотеки);
- настройку NAT для videobridge (по флагу `--nat`).

## Ручная установка

### Шаг 1. Отключить zram (рекомендуется на 2–4 GB RAM)

```bash
sudo swapoff -a
sudo systemctl disable armbian-zram-config.service
sudo systemctl disable armbian-ramlog.service
```

### Шаг 2. Hostname и /etc/hosts

```bash
sudo hostnamectl set-hostname meet.example.org
echo "192.168.1.10 meet.example.org" | sudo tee -a /etc/hosts
```

### Шаг 3. Репозитории Prosody и Jitsi

```bash
sudo apt install -y apt-transport-https curl gnupg2 lua5.2 nginx-full openjdk-17-jre-headless

# Prosody
sudo curl -sL https://prosody.im/files/prosody-debian-packages.key \
  -o /usr/share/keyrings/prosody-debian-packages.key
echo "deb [signed-by=/usr/share/keyrings/prosody-debian-packages.key] http://packages.prosody.im/debian $(lsb_release -sc) main" \
  | sudo tee /etc/apt/sources.list.d/prosody-debian-packages.list

# Jitsi
curl -sL https://download.jitsi.org/jitsi-key.gpg.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/jitsi-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/" \
  | sudo tee /etc/apt/sources.list.d/jitsi-stable.list

sudo apt update
```

### Шаг 4. Firewall

```bash
sudo ufw allow 80,443/tcp
sudo ufw allow 10000/udp
sudo ufw allow 22/tcp
sudo ufw enable
```

### Шаг 5. Установка Jitsi Meet

```bash
sudo apt install jitsi-meet
```

При установке укажите домен `meet.example.org` и выберите **Let's Encrypt certificates**.

Если сертификат не выпустился автоматически:

```bash
sudo /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh
```

### Шаг 6. ARM64: сборка libjnisctp (если видео не работает)

Остановите сервисы, соберите нативную библиотеку SCTP и замените JAR:

```bash
sudo systemctl stop prosody jitsi-videobridge2 jicofo
sudo apt install -y automake autoconf build-essential git libtool maven m4

git clone https://github.com/sctplab/usrsctp.git
git clone https://github.com/jitsi/jitsi-sctp
mv usrsctp jitsi-sctp/
cd jitsi-sctp

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
mvn package -DbuildSctp -DbuildNativeWrapper -DdeployNewJnilib -DskipTests

JNI_JAR=$(ls /usr/share/jitsi-videobridge/lib/jniwrapper-native-*.jar)
sudo cp jniwrapper/native/target/jniwrapper-native-1.0-SNAPSHOT.jar "$JNI_JAR"

sudo systemctl start prosody jitsi-videobridge2 jicofo
```

### Шаг 7. NAT (сервер за роутером)

Добавьте в `/etc/jitsi/videobridge/jvb.conf`:

```
ice4j {
  harvest {
    mapping {
      static-mappings = [
        {
          local-address = "192.168.1.10"
          public-address = "203.0.113.50"
        }
      ]
    }
  }
}
```

```bash
sudo systemctl restart jitsi-videobridge2
```

## Проверка

```bash
sudo systemctl status prosody jitsi-videobridge2 jicofo nginx
curl -I "https://meet.example.org"
```

Откройте `https://meet.example.org` в браузере и создайте тестовую конференцию с двумя участниками.

## Устранение неполадок

| Симптом | Решение |
|---------|---------|
| Нет видео/аудио между участниками | Проверьте проброс UDP 10000, NAT в `jvb.conf` |
| `UnsatisfiedLinkError: libjnisctp` | Пересоберите libjnisctp (шаг 6) |
| 3-й участник отключает остальных | Проверьте `/var/log/jitsi/jicofo.log`, RAM, SCTP |
| Мобильное приложение не подключается | Нужен валидный Let's Encrypt, не self-signed |
| OOM / зависания | `--disable-zram`, добавьте swap на SD/SSD |

Логи:

```bash
sudo tail -f /var/log/jitsi/jvb.log
sudo tail -f /var/log/jitsi/jicofo.log
sudo tail -f /var/log/prosody/prosody.log
```

## Удаление

```bash
sudo apt purge jigasi jitsi-meet jitsi-meet-web-config jitsi-meet-prosody \
  jitsi-meet-turnserver jitsi-meet-web jicofo jitsi-videobridge2
```

## Ссылки

- [Jitsi Handbook — Quick install](https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-quickstart)
- [Jitsi on ARM (GitHub issue)](https://github.com/jitsi/jitsi-meet/issues/6449)
- [jitsi-on-arm64 guide](https://github.com/cristianapas/jitsi-on-arm64)
