@echo off

echo Deploying Firestore indexes...
firebase deploy --only firestore:indexes