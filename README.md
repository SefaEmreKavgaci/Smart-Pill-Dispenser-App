# Smart Pill Dispenser Application

A Flutter application designed to manage medication schedules efficiently. This project offers a comprehensive frontend for both patients and caregivers.

## Getting Started

This application is built with Flutter and can be deployed easily as a Web application using Docker.

### Running with Docker

You can easily run this application without setting up a local Flutter environment by using Docker. The application will be built as a Flutter Web app and served via Nginx.

**Prerequisites:**
- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

**Steps to run:**

1. Clone the repository:
   ```bash
   git clone https://github.com/SefaEmreKavgaci/Smart-Pill-Dispenser-App.git
   cd Smart-Pill-Dispenser-App
   ```

2. Start the application using Docker Compose:
   ```bash
   docker-compose up -d
   ```

3. Open your web browser and navigate to:
   ```
   http://localhost:8080
   ```

To stop the application, run:
```bash
docker-compose down
```

### Running Locally (Development)

If you wish to run the app natively (iOS, Android, or Web) for development:

1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install)
2. Get the dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run
   ```

## Technologies Used
- **Flutter & Dart**: Cross-platform application framework
- **Firebase**: Backend services (Authentication, Realtime Database)
- **Hive**: Local storage solutions
- **Docker**: Containerization and easy deployment
