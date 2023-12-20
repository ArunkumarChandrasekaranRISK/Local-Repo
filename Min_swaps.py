def min_swaps_to_balance(sequence):
    stack = []
    swaps = 0

    for char in sequence:
        if char == "(": 
            stack.append(char)
        if char == ")":
            if not stack or stack[-1] == ")": stack.append(char)
            else: stack.pop()
    print(stack)
    while len(stack) > 0:
        if stack[0] !=  stack[-1]:
            stack.pop(0)
            stack.pop()
            swaps += 1
        else: swaps = -1; break
    return swaps

# Example usage:
sequence = "))()(())()(())("
result = min_swaps_to_balance(sequence)
print(result)
