#!/bin/bash

export PIP_ROOT_USER_ACTION=ignore

set -e

# Check for merge conflicts before proceeding
python -m compileall -f "${GITHUB_WORKSPACE}"
if grep -lr --exclude-dir=node_modules "^<<<<<<< " "${GITHUB_WORKSPACE}"
    then echo "Found merge conflicts"
    exit 1
fi

cd ~ || exit

pip install --upgrade pip
pip install frappe-bench

mysql --host 127.0.0.1 --port 3306 -u root -e "SET GLOBAL character_set_server = 'utf8mb4'"
mysql --host 127.0.0.1 --port 3306 -u root -e "SET GLOBAL collation_server = 'utf8mb4_unicode_ci'"

mysql --host 127.0.0.1 --port 3306 -u root -e "CREATE OR REPLACE DATABASE test_site"
mysql --host 127.0.0.1 --port 3306 -u root -e "CREATE OR REPLACE USER 'test_site'@'localhost' IDENTIFIED BY 'test_site'"
mysql --host 127.0.0.1 --port 3306 -u root -e "GRANT ALL PRIVILEGES ON \`test_site\`.* TO 'test_site'@'localhost'"

mysql --host 127.0.0.1 --port 3306 -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root'"  # match site_cofig
mysql --host 127.0.0.1 --port 3306 -u root -e "FLUSH PRIVILEGES"

echo BRANCH_NAME: "${BRANCH_NAME}"
git clone https://github.com/frappe/frappe --branch ${BRANCH_NAME}
bench init frappe-bench --frappe-path ~/frappe --python "$(which python)" --skip-assets --ignore-exist

mkdir ~/frappe-bench/sites/test_site
cp -r "${GITHUB_WORKSPACE}/.github/helper/site_config.json" ~/frappe-bench/sites/test_site/

cd ~/frappe-bench || exit

sed -i 's/watch:/# watch:/g' Procfile
sed -i 's/schedule:/# schedule:/g' Procfile
sed -i 's/socketio:/# socketio:/g' Procfile
sed -i 's/redis_socketio:/# redis_socketio:/g' Procfile

bench get-app payments https://github.com/frappe/payments --branch ${BRANCH_NAME} --skip-assets
bench get-app erpnext https://github.com/frappe/erpnext --branch ${BRANCH_NAME} --resolve-deps --skip-assets
bench get-app hrms https://github.com/frappe/hrms --branch ${BRANCH_NAME} --skip-assets
bench get-app check_run "${GITHUB_WORKSPACE}" --skip-assets

printf '%s\n' 'frappe' 'erpnext' 'payments' 'hrms' 'check_run' > ~/frappe-bench/sites/apps.txt
bench setup requirements --python
bench use test_site

bench start &> bench_run_logs.txt &
CI=Yes &
bench --site test_site reinstall --yes --admin-password admin

bench setup requirements --dev

echo "BENCH VERSION NUMBERS:"
bench version
echo "SITE LIST-APPS:"
bench list-apps

bench start &> bench_run_logs.txt &
CI=Yes &
bench execute 'check_run.tests.setup.before_test'
