def min_swaps_to_balance(sequence):
    stack = []
    swaps = 0

    for char in sequence:
        if char == '(':
            stack.append(char)
        elif char == ')':
            if stack:
                stack.pop()
            else:
                swaps += 1

    swaps += len(stack) // 2

    return swaps

# Example usage:
sequence = ")()(())()"
result = min_swaps_to_balance(sequence)
print(result)
