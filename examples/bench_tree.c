/* Benchmark: Binary tree — equivalent to bench_tree_crystal.cr
 * 10 iterations of building depth-18 binary tree + check
 * ~5M allocations per iteration = ~50M total
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

typedef struct TreeNode {
    int32_t value;
    struct TreeNode* left;
    struct TreeNode* right;
} TreeNode;

TreeNode* make_tree(int depth) {
    TreeNode* node = (TreeNode*)malloc(sizeof(TreeNode));
    if (depth <= 0) {
        node->value = 1;
        node->left = NULL;
        node->right = NULL;
    } else {
        node->value = depth;
        node->left = make_tree(depth - 1);
        node->right = make_tree(depth - 1);
    }
    return node;
}

int32_t check_tree(TreeNode* node) {
    if (!node) return 0;
    return node->value + check_tree(node->left) - check_tree(node->right);
}

void free_tree(TreeNode* node) {
    if (!node) return;
    free_tree(node->left);
    free_tree(node->right);
    free(node);
}

int main(void) {
    int32_t result = 0;
    for (int i = 0; i < 10; i++) {
        TreeNode* tree = make_tree(18);
        result += check_tree(tree);
        free_tree(tree);
    }
    printf("%d\n", result);
    return 0;
}
