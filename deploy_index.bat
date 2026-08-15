@echo off

echo Deploying Firestore indexes...
npx firebase-tools deploy --only firestore:indexes