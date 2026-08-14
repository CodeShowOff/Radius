const admin = require('firebase-admin');

// Keep track of registered functions
export const registeredTriggers: any[] = [];
export const registeredCallables: Record<string, any> = {};

export function onDocumentCreated(opts: any, callback: any) {
  registeredTriggers.push({ type: 'created', opts, callback });
  return callback;
}

export function onDocumentUpdated(opts: any, callback: any) {
  registeredTriggers.push({ type: 'updated', opts, callback });
  return callback;
}

export function onDocumentDeleted(opts: any, callback: any) {
  registeredTriggers.push({ type: 'deleted', opts, callback });
  return callback;
}

export function onSchedule(opts: any, callback: any) {
  // Ignore schedule for now or could integrate node-cron
  registeredTriggers.push({ type: 'schedule', opts, callback });
  return callback;
}

export function onCall(opts: any, callback: any) {
  // opts could be options or just the callback if no options provided
  const cb = typeof opts === 'function' ? opts : callback;
  // We don't know the name here, we'll assign it when exporting
  return { isCallable: true, cb };
}

export class HttpsError extends Error {
  constructor(public code: string, message: string) {
    super(message);
  }
}

export const logger = {
  log: (...args: any[]) => console.log(...args),
  error: (...args: any[]) => console.error(...args),
  warn: (...args: any[]) => console.warn(...args),
  info: (...args: any[]) => console.info(...args),
};
