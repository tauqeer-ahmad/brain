def calculate_isbn13_check_digit(isbn)
  sum = 0
  isbn.chars.each_with_index do |digit, index|
    if index % 2 == 0
      sum += digit.to_i * 1
    else
      sum += digit.to_i * 3
    end
  end

  sum = sum % 10
  digit = 10 - sum
  digit
end
