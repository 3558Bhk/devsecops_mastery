# DSA Patterns - SDE3 Quick Revision (Must Know 15 Patterns)

## 1. Two Pointers
- Use: Sorted array, pair sum, remove duplicates, palindrome
- Example: Two sum sorted, container with most water
```java
int l=0, r=n-1;
while(l<r) {
  if (arr[l]+arr[r]==target) return true;
  else if (arr[l]+arr[r]<target) l++;
  else r--;
}
```

## 2. Sliding Window
- Use: Subarray/substring with condition, max sum k size, longest without repeating
- Fixed window size k, variable window
```java
// Fixed k max sum
int sum=0, max=0;
for(int i=0;i<n;i++) {
  sum+=arr[i];
  if(i>=k) sum-=arr[i-k];
  if(i>=k-1) max=Math.max(max,sum);
}
// Variable longest without repeating chars
int l=0, maxLen=0;
Map<Character,Integer> map=new HashMap<>();
for(int r=0;r<s.length();r++) {
  char c=s.charAt(r);
  if(map.containsKey(c) && map.get(c)>=l) l=map.get(c)+1;
  map.put(c,r);
  maxLen=Math.max(maxLen, r-l+1);
}
```

## 3. Fast & Slow Pointers (Floyd)
- Use: Linked list cycle detection, middle of list, palindrome linked list
```java
slow=fast=head;
while(fast!=null && fast.next!=null) {
  slow=slow.next;
  fast=fast.next.next;
  if(slow==fast) hasCycle=true;
}
// Middle: when fast reaches end slow at middle
```

## 4. Merge Intervals
- Use: Overlapping intervals, meeting rooms
```java
Arrays.sort(intervals, (a,b)->a[0]-b[0]);
List<int[]> merged=new ArrayList<>();
int[] cur=intervals[0];
for(int i=1;i<intervals.length;i++) {
  if(intervals[i][0]<=cur[1]) cur[1]=Math.max(cur[1], intervals[i][1]);
  else { merged.add(cur); cur=intervals[i]; }
}
merged.add(cur);
```

## 5. Cyclic Sort
- Use: Numbers in range 1 to n, find missing, duplicate
```java
int i=0;
while(i<n) {
  int correct=arr[i]-1;
  if(arr[i]!=arr[correct]) swap(arr,i,correct);
  else i++;
}
```

## 6. In-place Reversal of Linked List
```java
ListNode prev=null, curr=head;
while(curr!=null) {
  ListNode next=curr.next;
  curr.next=prev;
  prev=curr;
  curr=next;
}
return prev;
```

## 7. BFS (Level Order)
- Use: Shortest path unweighted, level order tree, connected components
```java
Queue<Node> q=new LinkedList<>();
q.add(root);
while(!q.isEmpty()) {
  int size=q.size();
  for(int i=0;i<size;i++) {
    Node cur=q.poll();
    // process
    if(cur.left!=null) q.add(cur.left);
    if(cur.right!=null) q.add(cur.right);
  }
}
```

## 8. DFS (Recursion/Stack)
- Use: Path, all combinations, tree traversal
- Preorder, inorder, postorder

## 9. Two Heaps
- Use: Median of stream, sliding window median
```java
PriorityQueue<Integer> maxHeap=new PriorityQueue<>(Collections.reverseOrder()); // lower half
PriorityQueue<Integer> minHeap=new PriorityQueue<>(); // upper half
// Balance: maxHeap size = minHeap or +1
// Median: if sizes equal avg of tops else maxHeap top
```

## 10. Subsets / Backtracking
- Use: Permutations, combinations, generate all subsets
```java
void backtrack(int start, List<Integer> path) {
  result.add(new ArrayList<>(path));
  for(int i=start;i<n;i++) {
    path.add(nums[i]);
    backtrack(i+1, path);
    path.remove(path.size()-1);
  }
}
```

## 11. Binary Search (Many Variants)
- Use: Sorted array search, search in rotated, find peak, first/last occurrence
```java
int l=0, r=n-1;
while(l<=r) {
  int m=l+(r-l)/2;
  if(arr[m]==target) return m;
  else if(arr[m]<target) l=m+1;
  else r=m-1;
}
// Lower bound first >= target
// Upper bound first > target
```

## 12. Top K Elements (Heap)
- Use: K largest, K frequent, top K
```java
PriorityQueue<Integer> minHeap=new PriorityQueue<>(k);
for(int num: arr) {
  minHeap.add(num);
  if(minHeap.size()>k) minHeap.poll();
}
```

## 13. K-way Merge
- Use: Merge k sorted lists, arrays
```java
PriorityQueue<Node> pq=new PriorityQueue<>((a,b)->a.val-b.val);
for(Node head: lists) if(head!=null) pq.add(head);
Node dummy=new Node(0), curr=dummy;
while(!pq.isEmpty()) {
  Node node=pq.poll();
  curr.next=node; curr=curr.next;
  if(node.next!=null) pq.add(node.next);
}
```

## 14. Dynamic Programming (Top patterns)

- **0/1 Knapsack**: Subset sum, equal partition
- **Unbounded Knapsack**: Coin change
- **Fibonacci**: Climbing stairs
- **Longest Common Subsequence**: LCS, edit distance
- **Longest Increasing Subsequence**: LIS
- **Palindromic**: Longest palindromic substring
- **Grid**: Unique paths

Template:
```java
// 1D DP
int[] dp=new int[n+1];
dp[0]=0;
for(int i=1;i<=n;i++) dp[i]=Math.min(dp[i-1], dp[i-2])+cost[i];

// 2D DP
int[][] dp=new int[m+1][n+1];
for...
```

## 15. Greedy
- Use: Activity selection, interval scheduling, Huffman, Dijkstra

## Must Know Data Structures Complexities

| DS | Access | Search | Insert | Delete | Space |
|----|--------|--------|--------|--------|-------|
| Array | O(1) | O(n) | O(n) | O(n) | O(n) |
| LinkedList | O(n) | O(n) | O(1) | O(1) | O(n) |
| Stack | O(n) | O(n) | O(1) | O(1) | O(n) |
| Queue | O(n) | O(n) | O(1) | O(1) | O(n) |
| HashMap | - | O(1) avg O(n) worst | O(1) | O(1) | O(n) |
| TreeMap | O(log n) | O(log n) | O(log n) | O(log n) | O(n) |
| Heap | - | O(n) | O(log n) | O(log n) | O(n) |

## Sorting Complexities

| Sort | Best | Avg | Worst | Space | Stable |
|------|------|-----|-------|-------|--------|
| Quick | O(n log n) | O(n log n) | O(n^2) | O(log n) | No |
| Merge | O(n log n) | O(n log n) | O(n log n) | O(n) | Yes |
| Heap | O(n log n) | O(n log n) | O(n log n) | O(1) | No |
| Bubble | O(n) | O(n^2) | O(n^2) | O(1) | Yes |

## Top SDE3 Coding Questions to Practice (15)

1. LRU Cache (HashMap + Doubly Linked List)
2. Two Sum, Three Sum
3. Longest Substring Without Repeating
4. Merge Intervals
5. Valid Parentheses
6. Reverse Linked List, Detect Cycle
7. Binary Tree Level Order, LCA
8. Kth Largest Element (Heap)
9. Coin Change (DP)
10. Word Ladder (BFS)
11. Course Schedule (Topological Sort)
12. Number of Islands (DFS/BFS)
13. Median of Two Sorted Arrays (Binary Search)
14. Design Rate Limiter (System Design + Code)
15. Implement Trie, Autocomplete

## Tips

- Always ask clarifying: Constraints? Input size? Edge cases?
- Think brute force first then optimize
- Use hash map for O(1) lookup
- For linked list consider dummy node
- For tree consider recursion + iterative
- Time and space complexity analysis mandatory
