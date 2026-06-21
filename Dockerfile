# Usa a imagem oficial do Ubuntu 24.04
FROM ubuntu:24.04

# Evita prompts interativos durante a instalação de pacotes
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && apt-get upgrade -y && \
    apt-get install -y wget curl gzip zip unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Executa o script oficial de instalação do DuckDB
RUN curl https://install.duckdb.org | sh

# Configura a variável de ambiente PATH apontando para a pasta do binário
ENV PATH="/root/.duckdb/cli/latest:${PATH}"

# Define o bash como entrada padrão
CMD ["/bin/bash"]
