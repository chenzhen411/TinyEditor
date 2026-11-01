import AppKit

/// Bounded lexical coloring only; never evaluates scripts or connects to a database.
enum ScriptHighlighting {
  enum Kind: String, CaseIterable {
    case comment, string, identifier, variable, keyword, number, escape
    var color: NSColor {
      switch self {
      case .comment: return .secondaryLabelColor
      case .string, .escape: return .systemRed
      case .identifier: return .systemTeal
      case .variable, .number: return .systemPurple
      case .keyword: return .systemBlue
      }
    }
  }
  struct Span {
    let range: NSRange
    let kind: Kind
  }

  // A single regex consumes comments and quoted units before keywords, so their
  // contents cannot be recolored by subsequent matches. Compile once per mode.
  private static let shell = compile([
    (.comment, #"(?<![^\s;|&()<>])#[^\r\n]*"#),
    (.escape, #"\\[\s\S]"#),
    (.string, #"'(?:[^'])*(?:'|\z)|"(?:\\[\s\S]|[^"\\])*(?:"|\z)|`(?:\\[\s\S]|[^`\\])*(?:`|\z)"#),
    (.variable, #"\$(?:\{[^}\r\n]*\}|[A-Za-z_][A-Za-z_0-9]*|[0-9@*#?$!_-])"#),
    (.keyword, #"\b(?:if|then|elif|else|fi|for|while|until|do|done|case|in|esac|select|function|time|export|local|readonly|declare|typeset|set|unset|trap|read|source|alias|unalias|type|command|test|eval|exec|return|exit|break|continue|shift|wait|echo|printf|cd|pwd)\b"#),
    (.number, #"(?<![\w])\d+(?:\.\d+)?\b"#),
  ])
  private static let sql = compile([
    (.comment, #"--[^\r\n]*|/\*[\s\S]*?(?:\*/|\z)"#),
    (.string, #"'(?:''|[^'])*(?:'|\z)"#),
    (.identifier, #""(?:""|[^"])*(?:"|\z)|`(?:``|[^`])*(?:`|\z)|\[(?:\]\]|[^\]])*(?:\]|\z)"#),
    (.variable, #"(?<!:)\:[A-Za-z_][A-Za-z_0-9]*|\$\d+|@[A-Za-z_][A-Za-z_0-9]*|\?"#),
    (.keyword, #"\b(?:select|from|where|insert|into|values|update|set|delete|create|alter|drop|table|view|index|database|schema|temporary|if|exists|not|and|or|as|join|inner|left|right|full|outer|cross|on|using|group|by|order|having|limit|offset|fetch|union|all|distinct|intersect|except|with|recursive|case|when|then|else|end|is|null|true|false|like|ilike|between|in|asc|desc|nulls|first|last|primary|foreign|key|references|unique|check|default|constraint|begin|commit|rollback|transaction|truncate|replace|returning|over|partition|rows|range|cast|coalesce|count|sum|avg|min|max|int|integer|bigint|smallint|decimal|numeric|real|float|double|boolean|bool|char|varchar|text|date|time|timestamp|interval|blob|json|jsonb)\b"#),
    (.number, #"(?<![\w])(?:0x[0-9a-f]+|\d+(?:\.\d*)?(?:e[+-]?\d+)?)\b"#),
  ], options: [.caseInsensitive])

  private static func compile(
    _ rules: [(Kind, String)], options: NSRegularExpression.Options = []
  ) -> NSRegularExpression {
    // These are fixed application patterns; a typo is caught by core checks/build acceptance.
    try! NSRegularExpression(
      pattern: rules.map { "(?<\($0.0.rawValue)>\($0.1))" }.joined(separator: "|"),
      options: options)
  }

  static func spans(in text: String, format: Format) -> [Span] {
    let regex: NSRegularExpression
    switch format {
    case .shell: regex = shell
    case .sql: regex = sql
    default: return []
    }
    return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
      .compactMap { match in
        for kind in Kind.allCases {
          let range = match.range(withName: kind.rawValue)
          if range.location != NSNotFound { return Span(range: range, kind: kind) }
        }
        return nil
      }
  }
}
