# Types of Databases - Revision

## 1. Relational (SQL) - RDBMS
- Structured, tables, rows, columns, schema fixed, ACID, SQL
- Examples: MySQL, PostgreSQL, Oracle, SQL Server, MariaDB
- Use: Transactions, banking, ERP, strong consistency needed
- Scaling: Vertical, read replicas, sharding (hard)
- Pros: ACID, joins, mature
- Cons: Schema rigid, scaling hard

## 2. NoSQL - 4 Types

### a) Document Store
- JSON-like documents, flexible schema, nested
- Examples: MongoDB, CouchDB, Firestore
- Use: CMS, catalogs, user profiles, flexible schema
- Query: Rich queries, indexing on fields
- Pros: Flexible, developer friendly
- Cons: Joins hard, transactions limited (Mongo now supports multi-doc ACID)

### b) Key-Value
- Simple key-value, super fast
- Examples: Redis, DynamoDB, Riak, Memcached
- Use: Caching, session store, shopping cart, leaderboard
- Pros: Extremely fast O(1), scalable
- Cons: No complex queries, only key lookup

### c) Column-Family / Wide-Column
- Columns grouped, rows can have different columns, optimized for large scale
- Examples: Cassandra, HBase, ScyllaDB, Bigtable
- Use: Time-series, IoT, logging, big data write heavy, e.g. Netflix viewing history
- Pros: Massive scale, high write throughput, tunable consistency
- Cons: No joins, query limited to PK, eventual consistency

### d) Graph
- Nodes + edges + properties, optimized for relationships
- Examples: Neo4j, Amazon Neptune, ArangoDB
- Use: Social network, recommendation engine, fraud detection, knowledge graph
- Query: Cypher (Neo4j), Gremlin
- Pros: Relationship queries super fast
- Cons: Not for large blobs, scaling hard

## 3. Other Types

### Time-Series
- Optimized for time-stamped data
- Examples: InfluxDB, TimescaleDB (PG extension), Prometheus, Timestream
- Use: Metrics, IoT sensors, stock prices

### Search / Full-Text
- Inverted index for search
- Examples: Elasticsearch, OpenSearch, Solr, MeiliSearch
- Use: Search engine, log analytics, autocomplete

### Vector Database (New - AI)
- Stores embeddings for similarity search
- Examples: Pinecone, Weaviate, Qdrant, Milvus, pgvector
- Use: RAG for LLM, image search, recommendation

### In-Memory
- Data in RAM, ultra fast, persistence optional
- Examples: Redis, Memcached

### NewSQL
- SQL + NoSQL scalability, distributed ACID
- Examples: CockroachDB, TiDB, Google Spanner, YugabyteDB
- Use: Global distributed transactions

## CAP & Database Choice

| Need | Choose |
|------|--------|
| Strong consistency + transactions | RDBMS (PG) |
| Flexible schema + scale | MongoDB |
| Ultra fast cache/session | Redis |
| High write scale + time series | Cassandra |
| Relationships | Neo4j |
| Search | Elasticsearch |
| Global scale + ACID | Spanner/Cockroach |
| AI similarity | Vector DB |

## SQL vs NoSQL Comparison

| Feature | SQL | NoSQL |
|---------|-----|-------|
| Schema | Fixed | Flexible |
| Scale | Vertical + read replica | Horizontal easy |
| Transactions | ACID strong | BASE eventual (many now ACID) |
| Joins | Yes powerful | Limited / denormalize |
| Use | Structured, transactions | Unstructured, big data, rapid dev |

## Important Concepts

### Normalization vs Denormalization
- Normalization: Reduce redundancy, 1NF,2NF,3NF, good for write, need joins for read
- Denormalization: Duplicate data for fast read, good for read heavy, NoSQL does this

### Indexes
- B-Tree (default for RDBMS, range queries), Hash (key-value), GiST/GIN (PG full text), Inverted (search)
- Covering index: Index includes all columns needed, no table lookup
- Pros: Fast read, Cons: Slow write, storage
- Too many indexes = slow writes

### Replication
- Master-Slave: Writes master, reads slaves, async/sync
- Master-Master: Both write, conflict resolution needed

### Sharding
- Horizontal partitioning by key (e.g. user_id % 4)
- Pros: Scale write
- Cons: Cross-shard queries hard, rebalancing hard, choose shard key carefully to avoid hot shard
- Strategies: Range, Hash, Directory, Geo

### Consistency Levels (Cassandra/Dynamo)
- ONE, QUORUM, ALL
- QUORUM: (RF/2)+1 - balance consistency & availability

## Interview Q: When to use which?
"For our e-commerce: PG for orders/payments (ACID), Mongo for product catalog (flexible attributes), Redis for cart/session/cache, Elasticsearch for product search, Cassandra for order history time-series, Neo4j for recommendation graph if needed."
