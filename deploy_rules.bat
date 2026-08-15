@echo off

echo Deploying Firestore rules...
npx firebase-tools deploy --only firestore:rules