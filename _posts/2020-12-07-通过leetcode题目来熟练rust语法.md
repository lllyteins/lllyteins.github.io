---
layout: post
title:  "通过leetcode题目来熟练rust语法"
date:   2020-12-07 23:10:43
comments: true
categories:

---
还是拒绝不了rust性能的魅力, 所以这段时间没有持续的新业务接入, 终于有时间学一下rust了. 看了一遍the book, 忘的比记住的多. 所以在看别的项目的代码的同时，通过做一点leetcode的题目来熟练一下语法吧。

```rust
use std::collections::HashMap;
use std::vec::Vec;

// 1. Two Sum
struct Solution {}

impl Solution {
    pub fn two_sum(nums: Vec<i32>, target: i32) -> Vec<i32> {
        let mut check = HashMap::new();
        let mut idx = 0;
        let mut result = Vec::new();
        for i in nums.iter() {
            let cur_check = target - i;
            match check.get(&cur_check) {
                Some(a) => {
                    result.push(*a);
                    result.push(idx);
                    return result;
                }
                None => {
                    check.insert(i, idx);
                    idx += 1;
                    continue;
                }
            }
        }
        return result;
    }
    pub fn two_sum_others(nums: Vec<i32>, target: i32) -> Vec<i32> {
        let mut index_hashmap = HashMap::with_capacity(nums.len());

        for (idx, &n) in nums.iter().enumerate() {
            let y = target - n;
            if let Some(&i) = index_hashmap.get(&y) {
                return vec![i as i32, idx as i32];
            } else {
                index_hashmap.insert(n, idx);
            }
        }
        vec![]
    }
}

#[cfg(test)]
mod tests {
    use crate::Solution;

    #[test]
    fn solution_1() {
        let input_data = vec![2, 7, 11, 15];
        let target = 9;
        let correct_result = vec![0, 1];
        assert_eq!(Solution::two_sum(input_data, target), correct_result);
    }
}
```
