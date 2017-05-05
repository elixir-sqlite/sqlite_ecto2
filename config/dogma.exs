use Mix.Config
alias Dogma.Rule

config :dogma,
  rule_set: Dogma.RuleSet.All,

  override: [
    %Rule.CommentFormat{enabled: false},
    %Rule.FunctionArity{enabled: false},
    %Rule.LineLength{enabled: false},
    %Rule.PipelineStart{enabled: false},
    %Rule.QuotesInString{enabled: false},
  ]
