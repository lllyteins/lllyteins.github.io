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
# 词法分析
词法分析，也就是将原代码字符串切分为一个个的token，因此首先需要定义当前语言中所有的token。定义一个token数据结构为
```Go
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