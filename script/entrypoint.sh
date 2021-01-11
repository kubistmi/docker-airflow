#!/usr/bin/env bash

# User-provided configuration must always be respected.
#
# Therefore, this script must only derives Airflow AIRFLOW__ variables from other variables
# when the user did not provide their own configuration.

TRY_LOOP="20"

# Global defaults and back-compat
: "${AIRFLOW_HOME:="/usr/local/airflow"}"
: "${AIRFLOW__CORE__FERNET_KEY:=${FERNET_KEY:=$(python -c "from cryptography.fernet import Fernet; FERNET_KEY = Fernet.generate_key().decode(); print(FERNET_KEY)")}}"
: "${AIRFLOW__CORE__EXECUTOR:=${EXECUTOR:-Sequential}Executor}"

# Load DAGs examples (default: Yes)
if [[ -z "$AIRFLOW__CORE__LOAD_EXAMPLES" && "${LOAD_EX:=n}" == n ]]; then
  AIRFLOW__CORE__LOAD_EXAMPLES=False
fi

export \
  AIRFLOW_HOME \
  AIRFLOW__CORE__EXECUTOR \
  AIRFLOW__CORE__FERNET_KEY \
  AIRFLOW__CORE__LOAD_EXAMPLES \

# Install custom python package if requirements.txt is present
# if [ -e "/reqs/requirements.txt" ]; then
#     $(command -v pip) install --user -r /reqs/requirements.txt
# fi

wait_for_port() {
  local name="$1" host="$2" port="$3"
  local j=0
  while ! nc -z "$host" "$port" >/dev/null 2>&1 < /dev/null; do
    j=$((j+1))
    if [ $j -ge $TRY_LOOP ]; then
      echo >&2 "$(date) - $host:$port still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for $name... $j/$TRY_LOOP"
    sleep 5
  done
}


# Check if the user has provided explicit Airflow configuration concerning the database
if [ -z "$AIRFLOW__CORE__SQL_ALCHEMY_CONN" ]; then
  # Default values corresponding to the default compose files
  : "${POSTGRES_HOST:="postgres"}"
  : "${POSTGRES_PORT:="5432"}"
  : "${POSTGRES_USER:="airflow"}"
  : "${POSTGRES_PASSWORD:="airflow"}"
  : "${POSTGRES_DB:="airflow"}"
  : "${POSTGRES_EXTRAS:-""}"
  AIRFLOW__CORE__SQL_ALCHEMY_CONN="postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}${POSTGRES_EXTRAS}"
  export AIRFLOW__CORE__SQL_ALCHEMY_CONN
  # Check if the user has provided explicit Airflow configuration for the broker's connection to the database
  if [ "$AIRFLOW__CORE__EXECUTOR" = "CeleryExecutor" ]; then
    AIRFLOW__CELERY__RESULT_BACKEND="db+postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}${POSTGRES_EXTRAS}"
    export AIRFLOW__CELERY__RESULT_BACKEND
  fi
else
  if [[ "$AIRFLOW__CORE__EXECUTOR" == "CeleryExecutor" && -z "$AIRFLOW__CELERY__RESULT_BACKEND" ]]; then
    >&2 printf '%s\n' "FATAL: if you set AIRFLOW__CORE__SQL_ALCHEMY_CONN manually with CeleryExecutor you must also set AIRFLOW__CELERY__RESULT_BACKEND"
    exit 1
  fi
  # Derive useful variables from the AIRFLOW__ variables provided explicitly by the user
  POSTGRES_ENDPOINT=$(echo -n "$AIRFLOW__CORE__SQL_ALCHEMY_CONN" | cut -d '/' -f3 | sed -e 's,.*@,,')
  POSTGRES_HOST=$(echo -n "$POSTGRES_ENDPOINT" | cut -d ':' -f1)
  POSTGRES_PORT=$(echo -n "$POSTGRES_ENDPOINT" | cut -d ':' -f2)
fi
wait_for_port "Postgres" "$POSTGRES_HOST" "$POSTGRES_PORT"


# CeleryExecutor drives the need for a Celery broker, defaults to RabbitMQ
if [ "$AIRFLOW__CORE__EXECUTOR" = "CeleryExecutor" ]; then
  # Check if the user has provided explicit Airflow configuration concerning the broker
  if [ -z "$AIRFLOW__CELERY__BROKER_URL" ]; then
    # Default values corresponding to the default compose files
    : "${QUEUE_PROTO:="amqp://"}"
    : "${QUEUE_HOST:="queue"}"
    : "${QUEUE_PORT:="5672"}"
    : "${QUEUE_USER:="admin"}"
    : "${QUEUE_PASSWORD:="mypass"}"
    AIRFLOW__CELERY__BROKER_URL="${QUEUE_PROTO}${QUEUE_USER}:${QUEUE_PASSWORD}@${QUEUE_HOST}:${QUEUE_PORT}"
    export AIRFLOW__CELERY__BROKER_URL
  else
    # Derive useful variables from the AIRFLOW__ variables provided explicitly by the user
    QUEUE_ENDPOINT=$(echo -n "$AIRFLOW__CELERY__BROKER_URL" | cut -d '/' -f3 | sed -e 's,.*@,,')
    QUEUE_HOST=$(echo -n "$POSTGRES_ENDPOINT" | cut -d ':' -f1)
    QUEUE_PORT=$(echo -n "$POSTGRES_ENDPOINT" | cut -d ':' -f2)
  fi

  wait_for_port "Queue" "$QUEUE_HOST" "$QUEUE_PORT"
fi

case "$1" in
  webserver)
    airflow db init
    if [ "$AIRFLOW__CORE__EXECUTOR" = "LocalExecutor" ] || [ "$AIRFLOW__CORE__EXECUTOR" = "SequentialExecutor" ]; then
      # With the "Local" and "Sequential" executors it should all run in one container.
      airflow scheduler &
    fi
    airflow users create -u $2 -e $3 -f $4 -l $5 -p $6 -r Admin
    exec airflow webserver
    ;;
  scheduler)
    sleep 10
    exec airflow "$@"
    ;;
  worker)
    # Give the webserver time to run initdb.
    sleep 10
    exec airflow celery "$@"
    ;;
  flower)
    sleep 10
    exec airflow celery "$@"
    ;;
  version)
    exec airflow "$@"
    ;;
  *)
    # The command is something like bash, not an airflow subcommand. Just run it in the right environment.
    exec "$@"
    ;;
esac
