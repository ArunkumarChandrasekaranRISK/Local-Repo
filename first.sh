#!/bin/sh
# This is a comment!
echo Hello World        # This is a comment, too!

# Function to sum numeric elements of an array
sum_numeric_elements() {
    local sum=0
    for element in "${@}"; do
        if [[ $element =~ ^[0-9]+$ ]]; then
            sum=$((sum + element))
        fi
    done
    echo $sum
}

# Example usage
array=("apple" "123" "banana" "456" "cherry")
result=$(sum_numeric_elements "${array[@]}")
echo "Sum of numeric elements: $result"







