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
对于``tokio::spawn``中的数据，当调用``.await``时，需要将任务交给调度器，因此此时所有数据需要实现``Send``。比如如下程序
```Rust
use tokio::task::yield_now;
use std::rc::Rc;

#[tokio::main]
async fn main() {
    tokio::spawn(async {
        // The scope forces `rc` to drop before `.await`.
        {
            let rc = Rc::new("hello");
            println!("{}", rc);
        }

        // `rc` is no longer used. It is **not** persisted when
        // the task yields to the scheduler
        yield_now().await;
    });
}
```
由于当``yield_now().await``时，已经超过rc的生命周期，因此这段代码可以正常编译运行。但是，如
```Rust
use tokio::task::yield_now;
use std::rc::Rc;

#[tokio::main]
async fn main() {
    tokio::spawn(async {
        let rc = Rc::new("hello");

        // `rc` is used after `.await`. It must be persisted to
        // the task's state.
        yield_now().await;

        println!("{}", rc);
    });
}
```
当调用``yield_now().await``时，由于``rc``仍存在，但未实现``Send``，因此编译会报错如下
```Shell
error: future cannot be sent between threads safely
   --> src/main.rs:6:5
    |
6   |     tokio::spawn(async {
    |     ^^^^^^^^^^^^ future created by async block is not `Send`
    | 
   ::: [..]spawn.rs:127:21
    |
127 |         T: Future + Send + 'static,
    |                     ---- required by this bound in
    |                          `tokio::task::spawn::spawn`
    |
    = help: within `impl std::future::Future`, the trait
    |       `std::marker::Send` is not  implemented for
    |       `std::rc::Rc<&str>`
note: future is not `Send` as this value is used across an await
   --> src/main.rs:10:9
    |
7   |         let rc = Rc::new("hello");
    |             -- has type `std::rc::Rc<&str>` which is not `Send`
...
10  |         yield_now().await;
    |         ^^^^^^^^^^^^^^^^^ await occurs here, with `rc` maybe
    |                           used later
11  |         println!("{}", rc);
12  |     });
    |     - `rc` is later dropped here
```
可以看一下``tokio::spawn``的源码如下
```Rust
#[cfg_attr(tokio_track_caller, track_caller)]
pub fn spawn<T>(task: T) -> JoinHandle<T::Output>
where
    T: Future + Send + 'static,
    T::Output: Send + 'static,
{
    let spawn_handle = runtime::context::spawn_handle()
    .expect("must be called from the context of Tokio runtime configured with either `basic_scheduler` or `threaded_scheduler`");
    let task = crate::util::trace::task(task, "task");
    spawn_handle.spawn(task)
}
```
接下来，在``process``方法中，可以用一个``HashMap``存取kv，修改如下
```Rust
async fn process(socket: TcpStream) {
    use mini_redis::Command::{self, Get, Set};
    use std::collections::HashMap;

    // A hashmap is used to store data
    let mut db = HashMap::new();

    // Connection, provided by `mini-redis`, handles parsing frames from
    // the socket
    let mut connection = Connection::new(socket);

    // Use `read_frame` to receive a command from the connection.
    while let Some(frame) = connection.read_frame().await.unwrap() {
        let response = match Command::from_frame(frame).unwrap() {
            Set(cmd) => {
                // The value is stored as `Vec<u8>`
                db.insert(cmd.key().to_string(), cmd.value().to_vec());
                Frame::Simple("OK".to_string())
            }
            Get(cmd) => {
                if let Some(value) = db.get(cmd.key()) {
                    // `Frame::Bulk` expects data to be of type `Bytes`. This
                    // type will be covered later in the tutorial. For now,
                    // `&Vec<u8>` is converted to `Bytes` using `into()`.
                    Frame::Bulk(value.clone().into())
                } else {
                    Frame::Null
                }
            }
            cmd => panic!("unimplemented {:?}", cmd),
        };

        // Write the response to the client
        connection.write_frame(&response).await.unwrap();
    }
}
```
## 状态同步
连接之间可以通过加锁或线程通信实现状态同步，其中通常加锁的方式适用于简单的数据，而对于需要异步操作比如IO的数据，则会选择使用线程通信的方式，将状态信息通过通道交给一个单独的用于管理状态的线程处理。
### 锁(Shared state)
### 通道(Channels)


To Be Continued...