# frozen_string_literal: true

vial :users do
  base do
    active true
    country "MA"
    email sequence(:email)
  end

  variant :admin do
    role "admin"
  end

  variant :guest do
    role "guest"
    active false
  end

  sequence(:email) { |i| "user#{i}@test.local" }

  generate 2, :admin
  generate 3, :guest
end
