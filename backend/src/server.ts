import express from 'express';
import cors from 'cors';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import * as admin from 'firebase-admin';

// Initialize Firebase Admin first
const serviceAccountPath = path.join(__dirname, '..', 'serviceAccountKey.json');
if (fs.existsSync(serviceAccountPath)) {
  const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
  
  // Set environment variables for Google Auth Library (required by Firestore listeners)
  process.env.GOOGLE_APPLICATION_CREDENTIALS = serviceAccountPath;
  process.env.GCLOUD_PROJECT = serviceAccount.project_id;
  
  if (admin.apps.length === 0) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id
    });
  }
} else {
  console.warn("WARNING: serviceAccountKey.json not found in backend directory.");
  // It will crash if not initialized, but that's expected
}

import { registeredTriggers, registeredCallables } from './mock';
// This import executes the file and populates the mock arrays
import * as myFunctions from './index'; 

const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

// Set up Multer for Local Storage
const uploadDir = path.join(__dirname, '..', 'uploads');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({ storage: storage });

// Storage Endpoint
app.post('/api/upload', upload.single('file'), (req, res) => {
  if (!req.file) {
    return res.status(400).send('No file uploaded.');
  }
  // Return the URL to access the file
  const fileUrl = `${req.protocol}://${req.get('host')}/uploads/${req.file.filename}`;
  res.json({ url: fileUrl });
});

// Serve static files
app.use('/uploads', express.static(uploadDir));

// --- MAP CALLABLE FUNCTIONS TO EXPRESS ENDPOINTS ---
for (const [name, def] of Object.entries(myFunctions) as [string, any][]) {
  if (def.isCallable) {
    console.log(`Mapping callable function to endpoint: /api/${name}`);
    app.post(`/api/${name}`, async (req, res) => {
      try {
        // Construct the request object expected by onCall
        // Typical structure: { data: { ... }, auth: { uid: ... } }
        // For testing, if client doesn't pass auth, we simulate it or pass it along.
        // The Flutter app will send a standard POST with { data: ... }
        // We'll extract an auth token from headers if needed (simplified here)
        const authHeader = req.headers.authorization;
        let uid = null;
        if (authHeader && authHeader.startsWith('Bearer ')) {
          const idToken = authHeader.split('Bearer ')[1];
          if (idToken) {
            try {
              const decodedToken = await admin.auth().verifyIdToken(idToken);
              uid = decodedToken.uid;
            } catch (e) {
              console.error("Auth verify failed:", e);
            }
          }
        }
        
        // Sometimes Flutter clients send bare JSON without a `data` wrapper if we just use http.post
        // We'll adapt it so the function gets what it expects.
        const data = req.body;
        const callableReq = {
          data: data,
          auth: uid ? { uid } : null
        };

        const result = await def.cb(callableReq);
        // Functions typically return { data: result } automatically in the SDK, 
        // but since we aren't using the SDK client, we just return the raw JSON or wrapped JSON.
        // Let's return raw for simplicity, or wrapped if client expects it.
        res.json({ data: result });
      } catch (err: any) {
        console.error(`Error in ${name}:`, err);
        res.status(500).json({ error: { message: err.message, status: "INTERNAL" } });
      }
    });
  }
}

// --- SETUP FIRESTORE TRIGGERS ---
function setupTriggers() {
  const db = admin.firestore();
  const serverStartTime = Date.now();

  registeredTriggers.forEach((trigger) => {
    if (trigger.type === 'schedule') {
       console.log(`Scheduled task found (not implemented fully):`, trigger.opts);
       return;
    }

    const templatePath = typeof trigger.opts === 'string' ? trigger.opts : trigger.opts.document;
    if (!templatePath) return;

    // Convert "conversations/{conversationId}/messages/{messageId}"
    // to regex: ^conversations\/(?<conversationId>[^/]+)\/messages\/(?<messageId>[^/]+)$
    let regexStr = '^' + templatePath.replace(/\//g, '\\/') + '$';
    regexStr = regexStr.replace(/\{(\w+)\}/g, '(?<$1>[^/]+)');
    const pathRegex = new RegExp(regexStr);

    // Find the deepest collection name for collectionGroup
    const parts = templatePath.split('/');
    const collectionName = parts[parts.length - 2]; // Usually {col}/{doc}

    console.log(`Setting up ${trigger.type} trigger on collectionGroup('${collectionName}') for path ${templatePath}`);

    db.collectionGroup(collectionName).onSnapshot((snapshot) => {
      snapshot.docChanges().forEach(async (change) => {
        const docPath = change.doc.ref.path;
        const match = docPath.match(pathRegex);
        
        if (!match) return; // This document doesn't match the trigger template path

        const params = match.groups || {};
        
        // Prepare the event object
        const event: any = {
           params,
        };

        if (trigger.type === 'created' && change.type === 'added') {
           // Prevent processing old documents on server startup
           // If the readTime (snapshot time) is close to the document create time, it's a new document.
           // Since we can't reliably get create time from all docs, we'll check if the server just started.
           // Actually, docChanges() gives us everything on first load. Let's use the create time.
           const createTime = change.doc.createTime?.toMillis() || 0;
           // If the document was created before the server started (with 10 sec buffer), skip it!
           if (createTime > 0 && createTime < serverStartTime - 10000) {
             return;
           }

           event.data = change.doc; // DataSnapshot
           try { await trigger.callback(event); } catch(e) { console.error(e); }
        } 
        else if (trigger.type === 'updated' && change.type === 'modified') {
           // Provide a pseudo-Change object
           event.data = {
             before: null, // Hard to reconstruct before state without listening to every change perfectly
             after: change.doc
           };
           // Note: since this is dev, missing 'before' might break some specific functions.
           try { await trigger.callback(event); } catch(e) { console.error(e); }
        }
        else if (trigger.type === 'deleted' && change.type === 'removed') {
           event.data = change.doc;
           try { await trigger.callback(event); } catch(e) { console.error(e); }
        }
      });
    }, (error) => {
      console.error(`Error in listener for ${collectionName}:`, error);
    });
  });
}

// Wait a bit for initializeApp to finish if async, then setup triggers
setTimeout(() => {
  if (admin.apps.length > 0) {
    setupTriggers();
  }
}, 2000);


const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Backend server running on port ${PORT}`);
});
