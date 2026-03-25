# Calendarium

Кроссплатформенное приложение на Flutter. Репозиторий содержит исходный код, конфигурации платформ и инструкции для локального запуска и сборки.


## Требования

- Flutter SDK
- Dart SDK (идет вместе с Flutter)
- Android Studio или Xcode (для мобильных сборок)
- Удобнее всего работать в vscode 
- Для iOS сборок нужен macOS

Перед началом убедитесь что у вас установлен плагин, а также sdk flutter (IDE сама предложит их скачать)

Проверьте окружение:

```bash
flutter doctor
```

## Быстрый старт

```bash
flutter pub get
flutter run
```

По умолчанию `flutter run` запустит приложение на подключенном устройстве или эмуляторе.

## Запуск по платформам

Android:

```bash
flutter run -d android
```

iOS (только macOS):

```bash
cd ios
pod install
cd ..
flutter run -d ios
```

Web:

```bash
flutter run -d chrome
```

Web с ручным запуском:

```bash
flutter build web
cd build/web
python -m http.server 8080
```


Посмотреть список доступных девайсов:

```bash
flutter devices
```

## Сборка

Android APK:

```bash
flutter build apk --release
```

Android App Bundle:

```bash
flutter build appbundle
```

iOS (только macOS):

```bash
flutter build ios
```

Web:

```bash
flutter build web --release
```

Результаты сборки находятся в папке `build/`.

## Обратите внимание ##
Для запуска web-сборки ,а также на эмуляторе android нужно сменить IP-адрес на `http://127.0.0.1:8000` в файле `/api/api_client.dart`


```bash
if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }
    return 'http://127.0.0.1:8000';
```

Для запуска на приложения на другом устройстве укажите локальный IPv4-адрес устройства на котором развёрнут бекенд аналогично инструкции приведённой выше:

Узнать IPv4-адрес можно через команды:
```bash
ip a ## Linux and macos
ipconfig ## Windows
```


