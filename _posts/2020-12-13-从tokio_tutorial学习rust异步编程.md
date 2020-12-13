---
layout: post
title:  "从tokio_tutorial学习rust异步编程"
date:   2020-12-13 19:44:10
comments: true
categories:
- 
---
Rust的异步编程，主要使用``async``和``await``关键词，采用**生成器**对上下文进行保存，异步检查当前过程是否完成。Rust的异步编程库叫做[tokio](https://tokio.rs/tokio/tutorial)，官方文档中通过建立一个redis server和client来学习Rust异步编程。
## 使用基础
在安装完成所需的**mini-redis**库后，可以实现main函数为
```Rust
use mini_redis::{client, Result};

#[tokio::main]
pub async fn main() -> Result<()> {
    // Open a connection to the mini-redis address.
    let mut client = client::connect("127.0.0.1:6379").await?;

    // Set the key "hello" with value "world"
    client.set("hello", "world".into()).await?;

    // Get key "hello"
    let result = client.get("hello").await?;

    println!("got value from the server; result={:?}", result);

    Ok(())
}
```

观察上述代码，首先建立了一个由**mini-redis** crate实现的TCP连接，返回当前连接的handle。Rust的异步实现采用和同步近似的语法，仅需要在后面加``.await``运算符。有一个比较奇怪的地方，这里main函数也采用了``async``关键词，通常``main``函数用来启动我们的程序，都是同步运行，而异步函数通常需要交给运行时来管理其任务内容、IO、调度这些。在``main``函数前有``#[tokio::main]``这个宏，实际上其作用是将``main``函数从异步转为初始化一个运行时实例的同步函数，即将
```Rust
#[tokio::main]
async fn main() {
    println!("hello");
}
```
转化为
```Rust
fn main() {
    let mut rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        println!("hello");
    })
}
```
**Tokio**提供了众多常用类型如TCP, UDP, Unix sockets, timers, sync utilities, multiple scheduler types等，并大多采用与``std``中同步的同类型同名。接下来，将我们的服务绑定在6379端口用于建立与众多客户端的socket连接。
```Rust
use tokio::net::{TcpListener, TcpStream};
use mini_redis::{Connection, Frame};

#[tokio::main]
async fn main() {
    // Bind the listener to the address
    let listener = TcpListener::bind("127.0.0.1:6379").await.unwrap();

    loop {
        // The second item contains the IP and port of the new connection.
        let (socket, _) = listener.accept().await.unwrap();
        process(socket).await;
    }
}

async fn process(socket: TcpStream) {
    // The `Connection` lets us read/write redis **frames** instead of
    // byte streams. The `Connection` type is defined by mini-redis.
    let mut connection = Connection::new(socket);

    if let Some(frame) = connection.read_frame().await.unwrap() {
        println!("GOT: {:?}", frame);

        // Respond with an error
        let response = Frame::Error("unimplemented".to_string());
        connection.write_frame(&response).await.unwrap();
    }
}
```
服务程序持续循环检查端口情况，每当有新请求到来时，便会异步建立``socket``并调用``process``函数。此时还没有实现处理逻辑，所以对于所有请求，会返回*unimplemented*。此时分别调用服务端与客户端可以得到结果。
```shell
$ cargo run
$ cargo run --example hello-redis
Error: "unimplemented"
```
## 实现并发
此时虽然使用了``tokio``库，我们仍是顺序执行每个请求。为实现并发处理多个请求，对于建立的每个``socket``，将会调用``tokio::spawn``将任务交给一个异步的绿色线程。如下
```Rust
use tokio::net::TcpListener;

#[tokio::main]
async fn main() {
    let listener = TcpListener::bind("127.0.0.1:6379").await.unwrap();

    loop {
        let (socket, _) = listener.accept().await.unwrap();
        // A new task is spawned for each inbound socket. The socket is
        // moved to the new task and processed there.
        tokio::spawn(async move {
            process(socket).await;
        });
    }
}
```
这里使用了``move``关键词，将``socket``的所有权交给了这个``process``闭包。``tokio::spawn``会返回一个``JoinHandle``从而用于调用者与该异步任务进行交互，如
```Rust
#[tokio::main]
async fn main() {
    let handle = tokio::spawn(async {
        // Do some async work
        "return value"
    });

    // Do some other work

    let out = handle.await.unwrap();
    println!("GOT {}", out);
}
```
通过``JoinHandle``调用``await``将会返回一个``Result``类型的结果，若任务过程中发生错误，则该结果为``Err``。由于是绿色线程，所有异步任务由tokio调度器进行调度，在操作系统内核层面运行与同一线程之上。由于在用户态，因此十分轻量，仅占用64 bytes，因此可以轻松实现高并发。

需要注意的是，由于是异步运行，因此要求异步任务内所有变量生命周期应与外界无关，需要通过``move``关键词等方式移交所有权。如下述程序则会导致编译失败。
```Rust
use tokio::task;

#[tokio::main]
async fn main() {
    let v = vec![1, 2, 3];

    task::spawn(async {
        println!("Here's a vec: {:?}", v);
    });
}
```
## 实现**Send**方法



To Be Continued...