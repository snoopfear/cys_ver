# cys_ver

curl -fsSL https://raw.githubusercontent.com/snoopfear/cys_ver/refs/heads/main/install_cysic_ver.sh -o install_cysic_ver.sh && chmod +x install_cysic_ver.sh && ./install_cysic_ver.sh


UPDATE app docker

cd ~/cysic-verifier-docker && rm -f verifier && curl -L -o verifier https://github.com/cysic-labs/cysic-phase3/releases/download/v1.0.0/verifier_linux && chmod +x verifier && docker compose build && docker compose down && docker compose up -d

update number of containers

curl -fsSL https://raw.githubusercontent.com/snoopfear/cys_ver/refs/heads/main/add-verifiers.sh -o add-verifiers.sh && chmod +x add-verifiers.sh && ./add-verifiers.sh


UPDATE app screen

rm -f verifier && curl -L -o verifier https://github.com/cysic-labs/cysic-phase3/releases/download/v1.0.0/verifier_linux && chmod +x verifier && bash start.sh
