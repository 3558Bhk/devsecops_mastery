# Algorithms Quick Revision

## Binary Search Variants

### First Occurrence
```java
int firstOccurrence(int[] arr, int target) {
  int l=0,r=arr.length-1,ans=-1;
  while(l<=r) {
    int m=l+(r-l)/2;
    if(arr[m]==target) { ans=m; r=m-1; }
    else if(arr[m]<target) l=m+1;
    else r=m-1;
  }
  return ans;
}
```

### Search in Rotated Sorted Array
```java
int l=0,r=n-1;
while(l<=r) {
  int m=l+(r-l)/2;
  if(arr[m]==target) return m;
  if(arr[l]<=arr[m]) { // left sorted
    if(target>=arr[l] && target<arr[m]) r=m-1;
    else l=m+1;
  } else { // right sorted
    if(target>arr[m] && target<=arr[r]) l=m+1;
    else r=m-1;
  }
}
```

## Sorting

### Quick Sort
```java
void quickSort(int[] arr, int low, int high) {
  if(low<high) {
    int pi=partition(arr,low,high);
    quickSort(arr,low,pi-1);
    quickSort(arr,pi+1,high);
  }
}
int partition(int[] arr, int low, int high) {
  int pivot=arr[high], i=low-1;
  for(int j=low;j<high;j++) if(arr[j]<pivot) { i++; swap(arr,i,j); }
  swap(arr,i+1,high);
  return i+1;
}
```

### Merge Sort
```java
void mergeSort(int[] arr, int l, int r) {
  if(l<r) {
    int m=l+(r-l)/2;
    mergeSort(arr,l,m);
    mergeSort(arr,m+1,r);
    merge(arr,l,m,r);
  }
}
```

## Graph Algorithms

### BFS Shortest Path Unweighted
- Use queue, visited set, distance array

### DFS
- Recursion or stack, visited set

### Dijkstra (Shortest Path Weighted, no negative)
```java
// PriorityQueue (dist, node)
int[] dist=new int[n]; Arrays.fill(dist, Integer.MAX_VALUE);
dist[src]=0;
PriorityQueue<int[]> pq=new PriorityQueue<>((a,b)->a[0]-b[0]);
pq.add(new int[]{0,src});
while(!pq.isEmpty()) {
  int[] cur=pq.poll();
  int d=cur[0], u=cur[1];
  if(d>dist[u]) continue;
  for(int[] edge: adj[u]) {
    int v=edge[0], w=edge[1];
    if(dist[u]+w < dist[v]) {
      dist[v]=dist[u]+w;
      pq.add(new int[]{dist[v], v});
    }
  }
}
```
- Complexity O((V+E) log V)

### Bellman-Ford (Handles negative, detects negative cycle)
- Relax all edges V-1 times, then one more time to detect negative cycle
- O(VE)

### Topological Sort (DAG)
- Kahn's BFS (indegree) or DFS
```java
// Kahn's
Queue<Integer> q=new LinkedList<>();
for(int i=0;i<V;i++) if(indegree[i]==0) q.add(i);
List<Integer> order=new ArrayList<>();
while(!q.isEmpty()) {
  int u=q.poll(); order.add(u);
  for(int v: adj[u]) { indegree[v]--; if(indegree[v]==0) q.add(v); }
}
if(order.size()!=V) hasCycle=true;
```

### Union-Find (Disjoint Set)
```java
class DSU {
  int[] parent, rank;
  DSU(int n) { parent=new int[n]; rank=new int[n]; for(int i=0;i<n;i++) parent[i]=i; }
  int find(int x) { if(parent[x]!=x) parent[x]=find(parent[x]); return parent[x]; } // path compression
  void union(int x,int y) {
    int px=find(x), py=find(y);
    if(px==py) return;
    if(rank[px]<rank[py]) parent[px]=py;
    else if(rank[px]>rank[py]) parent[py]=px;
    else { parent[py]=px; rank[px]++; }
  }
}
```
- Use: Cycle detection, connected components, Kruskal MST

### Kruskal MST
- Sort edges by weight, use DSU to add edge if not forming cycle

### Prim MST
- Similar to Dijkstra, grow MST from source

## Tree Algorithms

### Traversals
- Inorder (Left Root Right) - BST sorted order
- Preorder (Root Left Right) - copy tree
- Postorder (Left Right Root) - delete tree
- Level order (BFS)

### LCA (Lowest Common Ancestor) BST
```java
TreeNode lca(TreeNode root, TreeNode p, TreeNode q) {
  if(p.val < root.val && q.val < root.val) return lca(root.left,p,q);
  if(p.val > root.val && q.val > root.val) return lca(root.right,p,q);
  return root;
}
```

### LCA Binary Tree
```java
TreeNode lca(TreeNode root, TreeNode p, TreeNode q) {
  if(root==null || root==p || root==q) return root;
  TreeNode left=lca(root.left,p,q);
  TreeNode right=lca(root.right,p,q);
  if(left!=null && right!=null) return root;
  return left!=null? left: right;
}
```

## Dynamic Programming Examples

### Fibonacci / Climbing Stairs
```java
// dp[i] = dp[i-1]+dp[i-2]
int climb(int n) {
  if(n<=2) return n;
  int a=1,b=2;
  for(int i=3;i<=n;i++) { int c=a+b; a=b; b=c; }
  return b;
}
```

### Coin Change (Min coins)
```java
int coinChange(int[] coins, int amount) {
  int[] dp=new int[amount+1];
  Arrays.fill(dp, amount+1);
  dp[0]=0;
  for(int i=1;i<=amount;i++) {
    for(int coin: coins) if(coin<=i) dp[i]=Math.min(dp[i], dp[i-coin]+1);
  }
  return dp[amount]>amount? -1: dp[amount];
}
```

### LCS
```java
int lcs(String s1, String s2) {
  int m=s1.length(), n=s2.length();
  int[][] dp=new int[m+1][n+1];
  for(int i=1;i<=m;i++) for(int j=1;j<=n;j++) {
    if(s1.charAt(i-1)==s2.charAt(j-1)) dp[i][j]=dp[i-1][j-1]+1;
    else dp[i][j]=Math.max(dp[i-1][j], dp[i][j-1]);
  }
  return dp[m][n];
}
```

## Bit Manipulation

- Check even: `(n & 1) == 0`
- Power of two: `(n & (n-1)) == 0` and n>0
- Count set bits: `n = n & (n-1)` loop
- XOR: Same 0 different 1, `a^a=0`, `a^0=a`
- Find single number where others twice: XOR all

## Important Complexities

- HashMap get/put O(1) avg
- TreeMap O(log n)
- Heap insert O(log n), get min O(1)
- QuickSort avg O(n log n)
- Binary search O(log n)
- BFS/DFS O(V+E)
- Dijkstra O((V+E) log V)
