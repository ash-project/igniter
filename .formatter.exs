spark_locals_without_parens = [attributes: 1, decrypt_by_default: 1, on_decrypt: 1, vault: 1]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test,installer}/**/*.{ex,exs}"],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
