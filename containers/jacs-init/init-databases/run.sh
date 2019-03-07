#!/bin/bash
#
# Initializes the database content.
#

if [[ -z "$MONGODB_INIT_ROOT_USERNAME" ]]; then
    echo "You must specify the env file containing the Mongo initialization parameters"
    exit 1
fi

set -e
DIR=$(cd "$(dirname "$0")"; pwd)

echo "Customizing RabbitMQ Environment"
RABBIT_CONF=$DIR/rabbitmq/rabbit_queues_config.json
TMP_RABBIT_CONF=/tmp/rabbit_queues_config.json
cp $RABBIT_CONF $TMP_RABBIT_CONF
RABBITMQ_PASSWORD_HASH=$(python $DIR/rabbitmq/hash.py $RABBITMQ_PASSWORD)
sed -i -e 's@RABBITMQ_USER@'"$RABBITMQ_USER"'@g' $TMP_RABBIT_CONF
sed -i -e 's@RABBITMQ_PASSWORD@'"$RABBITMQ_PASSWORD_HASH"'@g' $TMP_RABBIT_CONF

echo "Initializing RabbitMQ Data"
curl -v -u guest:guest -H "Content-Type: multipart/form-data" -H "Accept: application/json" -H "Expect:" -F file=@$TMP_RABBIT_CONF http://rabbitmq:15672/api/definitions
curl -v -u $RABBITMQ_USER:$RABBITMQ_PASSWORD -X DELETE http://rabbitmq:15672/api/users/guest

echo "Starting MongoDB replica set"
mongo mongodb://${MONGODB_INIT_ROOT_USERNAME}:${MONGODB_INIT_ROOT_PASSWORD}@mongo1:27017/${MONGODB_INIT_DATABASE} $DIR/mongo/replicaSet.js

echo "Initializing MongoDB Users"

cat >/tmp/createUserJacs.js <<EOL
db.createUser(
  {
    user: "${MONGODB_APP_USERNAME}",
    pwd: "${MONGODB_APP_PASSWORD}",
    roles: [ { role: "readWriteAnyDatabase", db: "admin" } ],
    passwordDigestor : "server"
  });
EOL

for filename in /tmp/*.js; do
    mongo mongodb://${MONGODB_INIT_ROOT_USERNAME}:${MONGODB_INIT_ROOT_PASSWORD}@mongo1:27017,mongo2:27017,mongo3:27017/${MONGODB_INIT_DATABASE}?replicaSet=rsJacs $filename
    sleep 1
done

