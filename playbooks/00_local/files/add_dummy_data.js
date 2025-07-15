// Credit System Dummy Data Script
// This script adds comprehensive dummy data for testing

print('🚀 Starting Credit System Dummy Data Population...');

// Switch to the credit_system database
db = db.getSiblingDB('credit_system');
print('📊 Using database: ' + db.getName());

// Helper function to generate random dates
function randomDate(start, end) {
  return new Date(start.getTime() + Math.random() * (end.getTime() - start.getTime()));
}

// Helper function to generate random amounts
function randomAmount(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// Helper function to pick random item from array
function randomChoice(array) {
  return array[Math.floor(Math.random() * array.length)];
}

print('👥 Creating dummy users...');

// Create multiple dummy users
const dummyUsers = [
  {
    email: 'john.doe@example.com',
    username: 'johndoe',
    password: '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj4J/HS.iQeO',
    status: 'active',
    profile: {
      first_name: 'John',
      last_name: 'Doe',
      phone: '+1-555-0101',
      country: 'US'
    }
  },
  {
    email: 'jane.smith@example.com', 
    username: 'janesmith',
    password: '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj4J/HS.iQeO',
    status: 'active',
    profile: {
      first_name: 'Jane',
      last_name: 'Smith', 
      phone: '+1-555-0102',
      country: 'CA'
    }
  },
  {
    email: 'bob.wilson@example.com',
    username: 'bobwilson', 
    password: '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj4J/HS.iQeO',
    status: 'active',
    profile: {
      first_name: 'Bob',
      last_name: 'Wilson',
      phone: '+1-555-0103', 
      country: 'UK'
    }
  },
  {
    email: 'alice.brown@example.com',
    username: 'alicebrown',
    password: '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj4J/HS.iQeO',
    status: 'active', 
    profile: {
      first_name: 'Alice',
      last_name: 'Brown',
      phone: '+1-555-0104',
      country: 'AU'
    }
  },
  {
    email: 'charlie.davis@example.com',
    username: 'charliedavis',
    password: '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj4J/HS.iQeO',
    status: 'suspended',
    profile: {
      first_name: 'Charlie',
      last_name: 'Davis',
      phone: '+1-555-0105',
      country: 'DE'
    }
  }
];

const createdUsers = [];
dummyUsers.forEach(function(userData) {
  if (db.users.countDocuments({email: userData.email}) === 0) {
    const user = {
      _id: ObjectId(),
      ...userData,
      created_at: randomDate(new Date(2024, 0, 1), new Date()),
      updated_at: new Date()
    };
    db.users.insertOne(user);
    createdUsers.push(user);
    print('    ✅ Created user: ' + user.email);
  } else {
    print('    ℹ️  User already exists: ' + userData.email);
  }
});

print('💰 Creating dummy wallets...');

// Create wallets for all users
const allUsers = db.users.find({}).toArray();
allUsers.forEach(function(user) {
  if (db.wallets.countDocuments({user_id: user._id}) === 0) {
    const wallet = {
      _id: ObjectId(),
      user_id: user._id,
      balance: randomAmount(0, 5000),
      currency: 'credits',
      created_at: user.created_at,
      updated_at: new Date()
    };
    db.wallets.insertOne(wallet);
    print('    ✅ Created wallet for ' + user.email + ' with ' + wallet.balance + ' credits');
  } else {
    print('    ℹ️  Wallet already exists for: ' + user.email);
  }
});

print('✅ Dummy data population complete!');
print('');
print('🧪 Test Users Created:');
allUsers.forEach(function(user) {
  const wallet = db.wallets.findOne({user_id: user._id});
  const balance = wallet ? wallet.balance : 0;
  print('  ' + user.email + ' (' + user.username + ') - ' + balance + ' credits');
});
print('');
print('🔑 All users have password: password123'); 