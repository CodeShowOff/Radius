@echo off

echo Deploying Firestore indexes...
firebase deploy --only firestore:indexes
npx firebase-tools deploy --only firestore:indexes