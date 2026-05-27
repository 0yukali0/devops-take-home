#!/bin/bash
set -e

mongosh --quiet \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    const emsDb = db.getSiblingDB('ems');
    const exists = emsDb.getUser('$MONGO_APP_USER');
    if (!exists) {
      emsDb.createUser({
        user: '$MONGO_APP_USER',
        pwd:  '$MONGO_APP_PASS',
        roles: [{ role: 'readWrite', db: 'ems' }]
      });
      print('app user created');
    } else {
      emsDb.updateUser('$MONGO_APP_USER', { pwd: '$MONGO_APP_PASS' });
      print('app user already exists, password synced');
    }
  "
