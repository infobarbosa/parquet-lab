# Usa a imagem oficial do Ubuntu 24.04
FROM ubuntu:24.04

# Evita prompts interativos durante a instalação de pacotes
ENV DEBIAN_FRONTEND=noninteractive

# Instala ferramentas básicas e Python
RUN apt-get update -y && apt-get upgrade -y && \
    apt-get install -y wget curl gzip zip unzip python3 python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Instalação do parquet-tools via pip
RUN pip3 install parquet-tools --break-system-packages

# Executa o script oficial de instalação do DuckDB
RUN curl https://install.duckdb.org | sh

# Configura a variável de ambiente PATH apontando para a pasta do binário
ENV PATH="/root/.duckdb/cli/latest:${PATH}"

# Define o diretório de trabalho padrão (onde os parquets serão salvos)
WORKDIR /workspace

# Define o bash como entrada padrão
CMD ["/bin/bash"]
