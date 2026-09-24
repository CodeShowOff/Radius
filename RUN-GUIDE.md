To test the app on a physical phone, your phone needs to connect to your computer over your local Wi-Fi network. 

`10.0.2.2` only works for emulators because it acts as a special proxy to your computer's `localhost`. For a real phone, you must use your computer's actual local IP address.

I ran `ipconfig` on your machine and found your local Wi-Fi IP address is: **`192.168.13.100`**. 
I went ahead and updated `lib/core/services/stream_token_service.dart` for you to use this IP!

### How to start it up:

**Step 1: Start the Backend**
1. Open a new terminal in your IDE.
2. Navigate to the backend folder:
   ```bash
   cd backend
   ```
3. Start your Node.js server:
   ```bash
   npm start
   ```
*(Your backend is already configured in `server.ts` to listen on `0.0.0.0`, which means it will accept connections from other devices on your Wi-Fi!)*

**Step 2: Run the Flutter App**
1. Ensure your phone and your computer are connected to the **exact same Wi-Fi network**.
2. Connect your phone via USB or Wireless debugging.
3. In a separate terminal, run your Flutter app onto your phone:
   ```bash
   flutter run
   ```

When the app launches on your phone, it will hit `http://192.168.13.100:3000/api/getStreamToken`, successfully reach your computer, verify your Firebase user, generate the Stream token, and log you into the chat!