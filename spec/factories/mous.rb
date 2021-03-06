FactoryGirl.define do
  factory :mou do
    sequence :ope do |n| DS::OpeId.pad(n.to_s) end

    institution { Faker::University.name }
    status { ["Probation - DoD", "Title IV Non-Compliant"].sample }

    trait :mou_probation do
      status "Probation - DoD"
    end
  end
end
