# ============================================================================
#  DynamoDB — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_dynamodb_table" "orders" {         # the table
  name         = "lab-orders"                    # the table's name (unique per region)
  billing_mode = "PAY_PER_REQUEST"               # pay per use (no capacity planning; free-tier friendly)

  hash_key  = "order_id"                         # the partition key (how items are sharded)
  range_key = null                               # no sort key for this table

  attribute {                                    # declare the partition key's type
    name = "order_id"                            # same as hash_key
    type = "S"                                   # S = string
  }

  attribute {                                    # declare the GSI key's type
    name = "status"                              # the indexed attribute
    type = "S"                                   # string
  }

  global_secondary_index {                        # the GSI: a second view keyed by status
    name            = "StatusIndex"               # the index name
    projection_type = "ALL"                       # index results carry all attributes
    hash_key        = "status"                    # the GSI's partition key
  }

  ttl {                                            # TTL: auto-delete expired items (free)
    attribute_name = "expires_at"                 # the unix-timestamp attribute
    enabled        = true                         # on
  }

  point_in_time_recovery { enabled = true }       # PITR: restore to any second in the last 35 days
  server_side_encryption { enabled = true }       # encrypt at rest (KMS default key)
}
