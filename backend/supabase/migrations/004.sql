CREATE TYPE goal_status AS ENUM ('ACTIVE', 'COMPLETED', 'CANCELLED');
CREATE TYPE transaction_type AS ENUM ('INCOME', 'EXPENSE');
CREATE TYPE transaction_category AS ENUM ('GROCERIES', 'UTILITIES', 'ENTERTAINMENT', 'SAVINGS', 'UNCATEGORIZED');

CREATE TABLE profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    full_name TEXT,
    current_balance DECIMAL(12, 2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now())
);

CREATE TABLE goals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    target_amount DECIMAL(12, 2) NOT NULL,
    saved_amount DECIMAL(12, 2) DEFAULT 0.00,
    deadline DATE,
    status goal_status DEFAULT 'ACTIVE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now())
);

CREATE TABLE transactions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    amount DECIMAL(12, 2) NOT NULL,
    description TEXT NOT NULL, -- سيستخدمه محرك Regex للتصنيف
    category transaction_category DEFAULT 'UNCATEGORIZED',
    type transaction_type NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now())
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;