# Exploração de Arquivos Parquet com DuckDB
- Author: Prof. Barbosa  
- Contact: infobarbosa@gmail.com  
- Github: [infobarbosa](https://github.com/infobarbosa)

## 1. Objetivo

- Explorar arquivos Parquet usando DuckDB
- Comparar tamanho dos arquivos no disco
- Comparar performance em diferentes cenários

## 2. Setup do Ambiente

Este laboratório é executado em Linux Ubuntu 24.04 (ou superior). Antes de começar, prepare seu ambiente instalando as dependências e baixando os dados.

ATENÇÃO! Se estiver utilizando Cloud9, utilize esse [tutorial](https://github.com/infobarbosa/data-engineering-cloud9).

### 2.A. Baixando a base de dados

A base que vamos utilizar está disponível para download no portal da transparência [aqui](https://portaldatransparencia.gov.br/download-de-dados/novo-bolsa-familia/202604).

### 2.B. Descompactando o arquivo CSV

No terminal do Linux, execute:

```bash
unzip 202604_NovoBolsaFamilia.zip
```

### 2.C. Instalando as Ferramentas

Instale o `parquet-tools` utilizando o gerenciador de pacotes do Python (`pip`):

```bash
pip install parquet-tools
```

Vamos instalar o DuckDB na versão mais recente para o Ubuntu:

```bash
curl https://install.duckdb.org | sh
```

Crie um link simbólico para o executável do DuckDB:

```bash
sudo ln -s ~/.duckdb/cli/latest/duckdb /usr/local/bin/duckdb
```

## 3. Preparação dos Dados (Limpeza em Tempo Real)

Inicie o DuckDB no terminal do Linux digitando o comando abaixo:

```bash
duckdb
```

Para não termos que reescrever o CSV inteiro em disco, vamos fazer o cast dos dados diretamente no DuckDB usando uma *Common Table Expression* (CTE) ou subquery. Note que em todas as queries a seguir, utilizaremos um `REPLACE` combinado com um `CAST` para converter o campo "VALOR PARCELA" (que contém vírgulas) para o tipo `DECIMAL(10,2)`.

Habilite o timer no DuckDB para analisar o tempo de execução no console:

```sql
.timer on
```

Opcional: Se desejar testar apenas a capacidade de I/O em processamento único, sem paralelismo:

```sql
SET threads = 1; 
```

---

## 4. Criando os Cenários (As Variantes Parquet)

Vamos criar 4 versões do mesmo arquivo para testar como o tamanho dos *Row Groups* e os algoritmos de compressão afetam o sistema. Execute as queries abaixo no CLI do DuckDB:

**1. O Padrão (Otimizado - ZSTD + Row Group Default)**
O DuckDB utiliza compressão ZSTD por padrão, oferecendo uma excelente taxa de compressão.

```sql
COPY (
    SELECT 
        *, 
        CAST(REPLACE("VALOR PARCELA", ',', '.') AS DECIMAL(10,2)) AS VALOR_NUMERICO
    FROM read_csv('202604_NovoBolsaFamilia.csv', encoding='latin-1', delim=';')
) TO 'bolsa_padrao.parquet' (FORMAT PARQUET, COMPRESSION 'ZSTD');
```

**2. Foco em Velocidade de Leitura (Snappy)**
O algoritmo Snappy comprime menos do que o ZSTD, resultando em arquivos maiores no disco, porém consome menos processamento (CPU) durante a descompressão.

```sql
COPY (
    SELECT 
        *, 
        CAST(REPLACE("VALOR PARCELA", ',', '.') AS DECIMAL(10,2)) AS VALOR_NUMERICO
    FROM read_csv('202604_NovoBolsaFamilia.csv', encoding='latin-1', delim=';')
) TO 'bolsa_snappy.parquet' (FORMAT PARQUET, COMPRESSION 'SNAPPY');
```

**3. Row Groups Minúsculos (Overhead de Metadados)**
Neste cenário forçamos grupos de apenas 10.000 linhas. Isso aumenta consideravelmente a proporção de metadados no arquivo, gerando um *footer* substancialmente maior.

```sql
COPY (
    SELECT 
        *, 
        CAST(REPLACE("VALOR PARCELA", ',', '.') AS DECIMAL(10,2)) AS VALOR_NUMERICO
    FROM read_csv('202604_NovoBolsaFamilia.csv', encoding='latin-1', delim=';')
) TO 'bolsa_rg_pequeno.parquet' (FORMAT PARQUET, ROW_GROUP_SIZE 10000);
```

**4. Row Groups Gigantes**
Forçando grupos de 1.000.000 de linhas. Otimizado para *Full Table Scans*, mas ineficiente para filtros muito granulares, pois exige o carregamento de blocos imensos de dados na memória.

```sql
COPY (
    SELECT 
        *, 
        CAST(REPLACE("VALOR PARCELA", ',', '.') AS DECIMAL(10,2)) AS VALOR_NUMERICO
    FROM read_csv('202604_NovoBolsaFamilia.csv', encoding='latin-1', delim=';')
) TO 'bolsa_rg_gigante.parquet' (FORMAT PARQUET, ROW_GROUP_SIZE 1000000);
```

---

## 5. Teste de I/O e Storage (Terminal do Sistema Operacional)

Saia do CLI do DuckDB para voltar ao terminal do Linux executando:

```sql
.exit
```

Vamos analisar os arquivos gerados no nível do sistema operacional.

Compare o tamanho real dos arquivos no disco:

```bash
ls -lh bolsa_*.parquet
```

Utilize o `parquet-tools` instalado no início do laboratório para inspecionar a quantidade de *Row Groups* alocada em cada arquivo:

```bash
parquet-tools inspect bolsa_padrao.parquet | grep "num_row_groups:"
```

```bash
parquet-tools inspect bolsa_rg_pequeno.parquet | grep "num_row_groups:"
```

```bash
parquet-tools inspect bolsa_rg_gigante.parquet | grep "num_row_groups:"
```

**O que observar:** O arquivo `bolsa_rg_pequeno.parquet` provavelmente será maior no disco do que o `padrao` ou o `gigante` devido ao excesso de metadados. Da mesma forma, o arquivo formatado com `snappy` será maior que o `padrao` (ZSTD).

---

## 6. Teste de Performance (No DuckDB)

Inicie o DuckDB novamente no terminal do Linux:

```bash
duckdb
```

Não se esqueça de habilitar o timer para os testes de stress:

```sql
.timer on
```

**Cenário A: O Agregador (Full Scan numa única coluna)**
O banco lerá apenas a coluna de valores, ignorando o restante da tabela. Execute a query abaixo para os 4 arquivos alterando apenas a cláusula `FROM`:

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

*Análise Técnica:* O arquivo `bolsa_rg_gigante.parquet` ou o `bolsa_snappy.parquet` tendem a apresentar o melhor desempenho aqui, pois a leitura sequencial de blocos grandes de apenas uma coluna evidencia a principal vantagem do formato colunar.

**Cenário B: O Filtro Empurrado (Predicate Pushdown)**
Vamos testar a estatística de metadados buscando por um estado específico.

```sql
SELECT "NOME FAVORECIDO", VALOR_NUMERICO 
FROM 'bolsa_rg_gigante.parquet' 
WHERE UF = 'AC';
```

*Análise Técnica:* O mecanismo de consulta analisará os metadados do arquivo (rodapé), verificará os valores mínimos e máximos da coluna `UF` por *Row Group* e descartará as leituras completas dos blocos que não possuírem dados do Acre. Compare o tempo de execução desta mesma query em relação ao arquivo `bolsa_padrao.parquet`.

**Cenário C: Sobrecarga em Buscas Pontuais (Point Lookups)**
Vamos buscar uma única linha usando um identificador único, e solicitar o retorno de todas as colunas.

```sql
SELECT * FROM 'bolsa_rg_pequeno.parquet' 
WHERE "NIS FAVORECIDO" = 16250240692; -- Use um NIS válido da sua base
```

*Análise Técnica:* Esta é uma das principais desvantagens dos formatos colunares. Para retornar `SELECT *`, o banco de dados precisa encontrar a linha correspondente através dos blocos colunares individuais e depois reconstruir o registro completo juntando fisicamente os valores separados. O arquivo particionado com *Row Groups* pequenos pode apresentar um desempenho levemente superior aqui, pois o bloco a ser descomprimido para encontrar o registro único é menor.

---

## 7. Inspeção do Plano de Execução (EXPLAIN ANALYZE)

Para comprovar fisicamente a eficiência do *Predicate Pushdown* (Filtro Empurrado), vamos inspecionar a árvore de execução gerada pelo banco de dados.

Com o DuckDB ainda aberto, utilize o comando `EXPLAIN ANALYZE` antes da query do cenário B:

```sql
EXPLAIN ANALYZE 
SELECT "NOME FAVORECIDO", VALOR_NUMERICO 
FROM 'bolsa_rg_gigante.parquet' 
WHERE UF = 'AC';
```

**Análise do Plano de Execução:**
Na saída gerada no console, observe a estrutura de árvore, com atenção especial ao nó `PARQUET_SCAN`. 

Analise as métricas de leitura apresentadas neste nó. Ele demonstrará de forma mensurável que o motor computacional leu os metadados do arquivo e utilizou as estatísticas de mínimo e máximo da coluna `UF` para ignorar completamente (*skip*) a leitura física dos blocos que não continham o estado do Acre. Isso prova matematicamente a economia substancial de I/O na consulta.

---

## Parabéns! 
Você aprendeu a analisar o formato Parquet de forma técnica, medindo o impacto real de diferentes configurações no sistema.
