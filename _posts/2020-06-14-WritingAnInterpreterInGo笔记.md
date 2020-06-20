---
layout: post
title:  "WritingAnInterpreterInGo笔记"
date:   2020-06-14 00:23:00
comments: true
---
这是本只有两百多页的书，主要讲了怎么用Go实现一个自定义的叫Monkey的语言的解释器。Monkey主要包括如下特点：
- C-like Syntax 类似C的语法 
- variable bindings 变量绑定(咋翻译？)
- integers and booleans 整数与布尔值
- arithmetic expressions 算术表达式
- built-in functions 内置函数(？)
- first-class and higher-order functions closures 一阶和高阶函数闭包
- a string data structure 字符串数据结构
- an array data structure 数组数据结构
- a hash data structure 哈希数据结构  
由此，这个解释器将会实现：
- the lexer 词法分析
- the parser 语法分析
- the Abstract Syntax Tree (AST) 抽象语法树
- the internal object system 内部对象系统(？)
- the evaluator 求值器(？)  
# Lexer
词法分析，也就是将原代码字符串切分为一个个的token，因此首先需要定义当前语言中所有的token。定义一个token数据结构为  

```go
type TokenType string
type Token struct {
	Type    TokenType
	Literal string
}
```
即由token类型与其值构成，如“5”的type是“INT”，字面值为“5”。  
另外，定义了所有的token类型，包括变量标识符、运算符、分隔符、关键词等。  

```go
const (
	ILLEGAL = "ILLEGAL"
	EOF     = "EOF"

	// Identifiers + literals
	IDENT = "IDENT" // add, foobar, x, y, ...
	INT   = "INT"   // 1343456

	// Operators
	ASSIGN   = "="
	PLUS     = "+"
	MINUS    = "-"
	BANG     = "!"
	ASTERISK = "*"
	SLASH    = "/"

	LT = "<"
	GT = ">"

	EQ     = "=="
	NOT_EQ = "!="

	// Delimiters
	COMMA     = ","
	SEMICOLON = ";"

	LPAREN = "("
	RPAREN = ")"
	LBRACE = "{"
	RBRACE = "}"

	// Keywords
	FUNCTION = "FUNCTION"
	LET      = "LET"
	TRUE     = "TRUE"
	FALSE    = "FALSE"
	IF       = "IF"
	ELSE     = "ELSE"
	RETURN   = "RETURN"
)
```
其中ILLEGAL表示非法、无法识别的token，EOF表示到达文件末尾，停止解析。  
准备好token后，就可以开始实现lexer。为了简化程序，这里并非采用读取文件的形式，而是输入一个字符串，然后每次调用NextToken()方法得到下一个token。定义lexer与其初始化方法为  

```go
type Lexer struct {
	input        string
	position     int  // current position in input (points to current char)
	readPosition int  // current reading position in input (after current char)
	ch           byte // current char under examination
}

func New(input string) *Lexer {
    l := &Lexer{input: input}
    l.readChar()
	return l
}
```
其中position指当前读到的位置，对应ch中保存的字符，readPosition指下一个应该读的位置。对应的readChar()方法为  

```go
func (l *Lexer) readChar() {
	if l.readPosition >= len(l.input) {
		l.ch = 0
	} else {
		l.ch = l.input[l.readPosition]
	}
	l.position = l.readPosition
	l.readPosition += 1
}
```
当读到文件末尾，在这里也就是字符串末尾时，将ch设置为0，对应ASCII码中的NUL。同样，在这里为了简化程序，仅使用ASCII而不使用Unicode。接下来就是完整的NextToken()方法。  

```go
func (l *Lexer) NextToken() token.Token {
	var tok token.Token

	l.skipWhitespace()

	switch l.ch {
	case '=':
		if l.peekChar() == '=' {
			ch := l.ch
			l.readChar()
			tok = token.Token{Type: token.EQ, Literal: string(ch) + string(l.ch)}
		} else {
			tok = newToken(token.ASSIGN, l.ch)
		}
	case '+':
		tok = newToken(token.PLUS, l.ch)
	case '-':
		tok = newToken(token.MINUS, l.ch)
	case '!':
		if l.peekChar() == '=' {
			ch := l.ch
			l.readChar()
			tok = token.Token{Type: token.NOT_EQ, Literal: string(ch) + string(l.ch)}
		} else {
			tok = newToken(token.BANG, l.ch)
		}
	case '/':
		tok = newToken(token.SLASH, l.ch)
	case '*':
		tok = newToken(token.ASTERISK, l.ch)
	case '<':
		tok = newToken(token.LT, l.ch)
	case '>':
		tok = newToken(token.GT, l.ch)
	case ';':
		tok = newToken(token.SEMICOLON, l.ch)
	case ',':
		tok = newToken(token.COMMA, l.ch)
	case '{':
		tok = newToken(token.LBRACE, l.ch)
	case '}':
		tok = newToken(token.RBRACE, l.ch)
	case '(':
		tok = newToken(token.LPAREN, l.ch)
	case ')':
		tok = newToken(token.RPAREN, l.ch)
	case 0:
		tok.Literal = ""
		tok.Type = token.EOF
	default:
		if isLetter(l.ch) {
			tok.Literal = l.readIdentifier()
			tok.Type = token.LookupIdent(tok.Literal)
			return tok
		} else if isDigit(l.ch) {
			tok.Type = token.INT
			tok.Literal = l.readNumber()
			return tok
		} else {
			tok = newToken(token.ILLEGAL, l.ch)
		}
	}

	l.readChar()
	return tok
}
```
其中涉及到的函数为  

```go
func (l *Lexer) skipWhitespace() {
	for l.ch == ' ' || l.ch == '\t' || l.ch == '\n' || l.ch == '\r' {
		l.readChar()
	}
}

func (l *Lexer) readChar() {
	if l.readPosition >= len(l.input) {
		l.ch = 0
	} else {
		l.ch = l.input[l.readPosition]
	}
	l.position = l.readPosition
	l.readPosition += 1
}

func (l *Lexer) peekChar() byte {
	if l.readPosition >= len(l.input) {
		return 0
	} else {
		return l.input[l.readPosition]
	}
}

func (l *Lexer) readIdentifier() string {
	position := l.position
	for isLetter(l.ch) {
		l.readChar()
	}
	return l.input[position:l.position]
}

func (l *Lexer) readNumber() string {
	position := l.position
	for isDigit(l.ch) {
		l.readChar()
	}
	return l.input[position:l.position]
}

func isLetter(ch byte) bool {
	return 'a' <= ch && ch <= 'z' || 'A' <= ch && ch <= 'Z' || ch == '_'
}

func isDigit(ch byte) bool {
	return '0' <= ch && ch <= '9'
}

func newToken(tokenType token.TokenType, ch byte) token.Token {
	return token.Token{Type: tokenType, Literal: string(ch)}
}
```
观察核心的NextToken()方法。首先，调用skipWhitespace()方法，跳过空格、换行等间隔符号。首先检查各类关键词、运算符、分隔符等。在涉及到二义性时，调用peekChar()方法进行检查，比如“=”与“==”，选择最长的一个。之后便是区分变量标识符与数字。现在，我们明白为什么变量命名的时候，不能以数字开头，只能字母或下划线了。  

```go
func LookupIdent(ident string) TokenType {
	if tok, ok := keywords[ident]; ok {
		return tok
	}
	return IDENT
}
```
在将变量标识符识别成功后，需要通过保存的关键词map进行查询确定是否是关键词。  
在完成lexer后，需要实现一个REPL(Read Eval Print Loop)，也就是类似于Python中的交互模式。具体为  

```go
func Start(in io.Reader, out io.Writer) {
	scanner := bufio.NewScanner(in)

	for {
		fmt.Printf(PROMPT)
		scanned := scanner.Scan()
		if !scanned {
			return
		}

		line := scanner.Text()
		l := lexer.New(line)

		for tok := l.NextToken(); tok.Type != token.EOF; tok = l.NextToken() {
			fmt.Printf("%+v\n", tok)
		}
	}
}
```
从main函数中启动REPL，将os.Stdin和os.Stdout传入该方法中，每次获取一行进行解析，返回所有的token。
# Parsing
parser的输入为从lexer得到的所有token，对其进行分析、构造得到抽象语法树(Abstract Syntax Tree, AST)。  
整体来看，所有的语句可以分为statement与expression，其中statement如“a = 1”，没有返回值；expression如“2 + 5”、“add(1, 2)”等，具有返回值。  
首先定义parser相关数据结构为
```go
type Parser struct {
	l *lexer.Lexer
	curToken token.Token
	peekToken token.Token 
}
func New(l *lexer.Lexer) *Parser { 
	p := &Parser{l: l}
	// Read two tokens, so curToken and peekToken are both set
	p.nextToken() p.nextToken()
	return p 
}
func (p *Parser) nextToken() { 
	p.curToken = p.peekToken p.peekToken = p.l.NextToken()
}
func (p *Parser) ParseProgram() *ast.Program { 		return nil
}
```
nextToken()等与lex中char相关类似。整体的parse逻辑可以近似表示为
```c++
function parseProgram() { 
	program = newProgramASTNode()
	advanceTokens()
	for (currentToken() != EOF_TOKEN) {
		statement = null
		if (currentToken() == LET_TOKEN) {
			statement = parseLetStatement()
		} else if (currentToken() == RETURN_TOKEN) {
			statement = parseReturnStatement()
		} else if (currentToken() == IF_TOKEN) {
			statement = parseIfStatement()
		}
		if (statement != null) {
			program.Statements.push(statement)
		}
		advanceTokens() 
	}
	return program 
}
function parseLetStatement() {
	advanceTokens()
	identifier = parseIdentifier()
	advanceTokens()
	if currentToken() != EQUAL_TOKEN {
		parseError("no equal sign!") return null
	}
	advanceTokens()
	value = parseExpression()
	variableStatement =newVariableStatementASTNode() variableStatement.identifier = identifier variableStatement.value = value
	return variableStatement
}
function parseIdentifier() {
	identifier = newIdentifierASTNode() identifier.token = currentToken()
	return identifier
}
function parseExpression() {
	if (currentToken() == INTEGER_TOKEN) {
		if (nextToken() == PLUS_TOKEN) {
			return parseOperatorExpression()
		} else if (nextToken() == SEMICOLON_TOKEN) {
			return parseIntegerLiteral()
		}
	} else if (currentToken() == LEFT_PAREN) {
		return parseGroupedExpression() 
	}
// [...]
}
function parseOperatorExpression() {
	operatorExpression = newOperatorExpression()
	operatorExpression.left = parseIntegerLiteral() 
	operatorExpression.operator = currentToken()
	operatorExpression.right = parseExpression()
	return operatorExpression()
}
// [...]
```
在parser中，将所有语句分为letstatement、returnstatement、expression等，采用recursive descent parser的方式，最终生成抽象语法树。例如输入
``let x = 1 * 2 * 3``得到``let x = ((1 * 2) * 3)``。作者比较喜欢parser这个环节，实际上现代编译器中更多倾向于探究后续的代码生成与优化环节，这部分我也是速读了一下，了解了一下整体的逻辑与构成，不在上面花太多时间。
# Evaluation
# Extending the Interpreter
后面两部分与现在做的事情暂时相关程度不高，先跳过(崩撤卖溜