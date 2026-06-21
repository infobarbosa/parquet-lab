# Exploração de Arquivos Parquet com DuckDB
- Author: Prof. Barbosa  
- Contact: infobarbosa@gmail.com  
- Github: [infobarbosa](https://github.com/infobarbosa)

## 1. Objetivo

- Explorar arquivos Parquet usando DuckDB
- Comparar tamanho dos arquivos no disco
- Comparar performance em diferentes cenários

## 2. Setup
Antes de começar, prepare seu ambiente:

- Base de dados do Bolsa Família de Abril de 2026
- DuckDB

ATENÇÃO! Se estiver utilizando Cloud9, utilize esse [tutorial](https://github.com/infobarbosa/data-engineering-cloud9).

### 2.A. Baixando a base de dados

A base que vamos utilizar está disponível para download no portal da transparência [aqui](https://portaldatransparencia.gov.br/download-de-dados/novo-bolsa-familia/202604).

### 2.B. Descompactando o arquivo CSV

```bash
unzip 202604_NovoBolsaFamilia.zip

```

### 2.C. Instalando o DuckDB
Vamos instalar o DuckDB na versão mais recente no Ubuntu.

```bash
curl https://install.duckdb.org | sh

```

```bash
# Cria um link simbólico para o executável do DuckDB
sudo ln -s ~/.duckdb/cli/latest/duckdb /usr/local/bin/duckdb

```

### Fase 0: Query Base (Limpeza em tempo real)

Para não termos que reescrever o CSV, vamos fazer o cast dos dados diretamente no DuckDB usando uma *Common Table Expression* (CTE) ou subquery. Vamos converter o `VALOR PARCELA` para `DECIMAL(10,2)`.

- Habilitando o timer no DuckDB para vermos o tempo de execução no console

```sql
.timer on

```

- Opcional: se quiser testar apenas a força bruta do I/O, sem paralelismo
```sql
SET threads = 1; 

```
---

### Fase 1: Criando os Cenários (As Variantes Parquet)

Vamos criar 4 versões do mesmo arquivo para testar como o tamanho dos *Row Groups* e os algoritmos de compressão afetam o sistema. Execute isso no seu CLI do DuckDB:

**1. O Padrão (Otimizado - ZSTD + Row Group Default)**
O DuckDB usa ZSTD por padrão, que tem uma taxa de compressão fantástica.

```sql
COPY (
    SELECT 
        *, 
        CAST(REPLACE("VALOR PARCELA", ',', '.') AS DECIMAL(10,2)) AS VALOR_NUMERICO
    FROM read_csv('202603_NovoBolsaFamilia.csv', encoding='latin-1', delim=';')
) TO 'bolsa_padrao.parquet' (FORMAT PARQUET, COMPRESSION 'ZSTD');

```

**2. Foco em Velocidade de Leitura (Snappy)**
Snappy comprime menos que o ZSTD, mas gasta menos CPU para descomprimir.

```sql
COPY (
    SELECT 
        *, 
        CAST(REPLACE("VALOR PARCELA", ',', '.') AS DECIMAL(10,2)) AS VALOR_NUMERICO
    FROM read_csv('202603_NovoBolsaFamilia.csv', encoding='latin-1', delim=';')
) TO 'bolsa_snappy.parquet' (FORMAT PARQUET, COMPRESSION 'SNAPPY');

```

**3. Row Groups Minúsculos (Overhead de Metadados)**
Forçando grupos de apenas 10.000 linhas. Isso vai inchar o arquivo com metadados (um *footer* enorme).

```sql
COPY (
    SELECT 
        *, 
        CAST(REPLACE("VALOR PARCELA", ',', '.') AS DECIMAL(10,2)) AS VALOR_NUMERICO
    FROM read_csv('202603_NovoBolsaFamilia.csv', encoding='latin-1', delim=';')
) TO 'bolsa_rg_pequeno.parquet' (FORMAT PARQUET, ROW_GROUP_SIZE 10000);

```

**4. Row Groups Gigantes**
Forçando grupos de 1.000.000 de linhas. Ótimo para *Full Scans*, mas péssimo para filtros granulares porque ele precisa carregar blocos imensos na memória de uma vez.

```sql
COPY (
    SELECT 
        *, 
        CAST(REPLACE("VALOR PARCELA", ',', '.') AS DECIMAL(10,2)) AS VALOR_NUMERICO
    FROM read_csv('202603_NovoBolsaFamilia.csv', encoding='latin-1', delim=';')
) TO 'bolsa_rg_gigante.parquet' (FORMAT PARQUET, ROW_GROUP_SIZE 1000000);

```

---

### Fase 2: Teste de I/O e Storage (No terminal do macOS)

Saia do DuckDB (ou abra outra aba do terminal) e vamos analisar os arquivos gerados no nível do sistema operacional:

- Compara o tamanho real no disco

```bash
ls -lh bolsa_*.parquet

```

- Se você ainda tiver o parquet-tools da nossa conversa anterior, olhe o tamanho do rodapé:
```bash

parquet-tools meta bolsa_rg_pequeno.parquet | grep "row group" | wc -l
```

```bash
parquet-tools meta bolsa_rg_gigante.parquet | grep "row group" | wc -l

```

**O que observar:** O `bolsa_rg_pequeno` provavelmente será maior no disco do que o `padrao` ou o `gigante` devido ao excesso de metadados. O `snappy` será maior que o `padrao` (ZSTD).

---

### Fase 3: Teste de Performance (No DuckDB)

Volte ao DuckDB com o `.timer on`. Vamos rodar testes de stress com as diferentes modelagens de arquivo.

**Cenário A: O Agregador (Full Scan numa única coluna)**
O Parquet deve ler apenas a coluna de valores e ignorar o resto. Rode isso para os 4 arquivos (substituindo o nome do arquivo).

```sql
SELECT UF, SUM(VALOR_NUMERICO) FROM 'bolsa_padrao.parquet' GROUP BY UF;

```

```sql
SELECT UF, SUM(VALOR_NUMERICO) FROM 'bolsa_snappy.parquet' GROUP BY UF;

```

```sql
SELECT UF, SUM(VALOR_NUMERICO) FROM 'bolsa_rg_gigante.parquet' GROUP BY UF;

```

```sql
SELECT UF, SUM(VALOR_NUMERICO) FROM 'bolsa_rg_pequeno.parquet' GROUP BY UF;

```

*Teoria:* O `bolsa_rg_gigante` ou o `bolsa_snappy` devem ganhar aqui, pois ler blocos grandes de forma sequencial é onde o Parquet brilha.

**Cenário B: O Filtro Empurrado (Predicate Pushdown)**
Vamos testar a estatística do rodapé. Procurar por um estado específico.

```sql
SELECT "NOME FAVORECIDO", VALOR_NUMERICO 
FROM 'bolsa_rg_gigante.parquet' 
WHERE UF = 'AC';

```

*Teoria:* O DuckDB vai olhar o rodapé do arquivo, ver as estatísticas da coluna `UF` e pular vários *Row Groups* inteiros se eles não contiverem o Acre. Compare o tempo dessa query entre o arquivo de *Row Group* gigante (que força a leitura de muita coisa inútil se o AC estiver no meio) e o arquivo padrão.

**Cenário C: O Ponto Cego (A fraqueza do Parquet)**
Buscar uma única linha usando um identificador único, trazendo todas as colunas.

```sql
SELECT * FROM 'bolsa_rg_pequeno.parquet' 
WHERE "NIS FAVORECIDO" = 16250240692; -- Use um NIS válido da sua base

```

*Teoria:* Esta é a "kryptonita" do formato colunar. Ele precisa achar a linha e depois "costurar" as 9 colunas separadas para te devolver o resultado. O arquivo de *Row Group* pequeno pode performar levemente melhor aqui do que o gigante, pois o bloco a ser descomprimido para achar essa agulha no palheiro é menor.

---

Esse laboratório vai te dar uma visão prática e mensurável de como o formato funciona por baixo dos panos.

Você gostaria que eu mostrasse também como inspecionar a árvore de execução (usando `EXPLAIN ANALYZE` no DuckDB) para vermos exatamente quantos *Row Groups* ele decidiu ler ou pular em cada uma dessas queries?

