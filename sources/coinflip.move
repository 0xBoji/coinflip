module fliptos::coinflip {

    // Module for the Fliptos Coin Flip
    // Implements the Native Randomness for a provably fair game

    use std::error;
    use std::signer;
    use std::vector;
    use std::string::String;
    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::randomness;
    use 0x1::fixed_point32::multiply_u64;
    use 0x1::fixed_point32;
    use 0x1::aptos_coin::AptosCoin;
    use 0x1::event::emit;
    use aptos_std::type_info;

    const FLIP_MULTIPLIER: u64 = 2;
    const FLIP_FEE_BPS: u64 = 250;
    const MAX_BET_APT: u64 = 2000_000_000;

    // treasury that players can play against
    struct Vault has key, store {
        vault_address: account::SignerCapability,
    }

    public entry fun create_vault(
        deployer: &signer
    ) {
        // check wallet doesn't already have a vault
        assert!(!exists<Vault>(signer::address_of(deployer)), error::not_found(0));

        // acquire a signer for the resource account that stores the coins
        let (_, vault_address) = account::create_resource_account(deployer, vector::empty());
        let rsrc_acc_signer  = account::create_signer_with_capability(&vault_address);

        // initialize an AptosCoin coin store there, which is where the vault APT will be kept
        coin::register<AptosCoin>(&rsrc_acc_signer);

        move_to(deployer, Vault {
            vault_address,
        })
    }

    // add coins to the specified vault
    public entry fun add_coins(
        from: &signer, owner_address: address, amount: u64) acquires Vault {

        assert!(exists<Vault>(owner_address), error::not_found(1));
        
        let from_balance: u64 = coin::balance<AptosCoin>(signer::address_of(from));
        assert!( amount <= from_balance, error::resource_exhausted(2));

        let vault = borrow_global_mut<Vault>(owner_address);

        let (_, rsrc_acc_address) = get_rsrc_acc(vault);

        coin::transfer<AptosCoin>(from, rsrc_acc_address, amount);
    }

    // withdraw coins from the vault
    public entry fun withdraw_coins(
        owner: &signer,
        amount: u64
    ) acquires Vault {
        let owner_address = signer::address_of(owner);

        // only vault owner can withdraw from his vault
        assert!(exists<Vault>(owner_address), error::not_found(3));

        let vault = borrow_global_mut<Vault>(owner_address);

        let (rsrc_acc_signer, _) = get_rsrc_acc(vault);

        coin::transfer<AptosCoin>(
            &rsrc_acc_signer,
            owner_address,
            amount);
    }

    // Coin Agnostic Withdraw Function
    public entry fun withdraw_coins_V2<CoinType>(
        owner: &signer,
        amount: u64
    ) acquires Vault {
        let owner_address = signer::address_of(owner);

        // only vault owner can withdraw from his vault
        assert!(exists<Vault>(owner_address), error::not_found(3));

        let vault = borrow_global_mut<Vault>(owner_address);

        let (rsrc_acc_signer, _) = get_rsrc_acc(vault);

        coin::transfer<CoinType>(
            &rsrc_acc_signer,
            owner_address,
            amount);
    }

    #[randomness]
    entry fun play(
        player: &signer,
        amount: u64,
        vault_owner: address // specifies against which vault player wants to bet
    ) acquires Vault {

        // check bet amount doesn't excess max
        assert!((amount < MAX_BET_APT), 4); 

        let player_address = signer::address_of(player);

        // check vault exists
        assert!(exists<Vault>(vault_owner), error::not_found(1));
        let vault = borrow_global_mut<Vault>(vault_owner);

        let from_balance: u64 = coin::balance<AptosCoin>(signer::address_of(player));
        assert!( amount <= from_balance, error::resource_exhausted(2));

        let (vault_rsrc_acc_signer, vault_rsrc_acc_addr) = get_rsrc_acc(vault);

        // 50% chance to win
        let flip_result = randomness::u64_range(0, 2);

        let fee_multiplier = fixed_point32::create_from_rational(10000 + FLIP_FEE_BPS, 10000);
        let amount_with_fees = multiply_u64(amount, fee_multiplier);

        // transfer bet amount + fees to the vault
        coin::transfer<AptosCoin>(player, vault_rsrc_acc_addr, amount_with_fees);

        if (flip_result == 1) {
            emit(FlipEvent {
                player: player_address,
                is_won: true,
                amount_bet: amount
                });
            
            // double bet amount
            let payout = amount * FLIP_MULTIPLIER;

            // rewards player
            coin::transfer<AptosCoin>(
                &vault_rsrc_acc_signer,
                player_address,
                payout);

        } else {
            emit(FlipEvent {
                player: player_address,
                is_won: false,
                amount_bet: amount
                });
        };
    }

    #[event]
    struct FlipEvent has drop, store {
        player: address,
        is_won: bool,
        amount_bet: u64
    }

    // Coin Agnostic Play Function
    #[randomness]
    entry fun play_V2<CoinType>(
        player: &signer,
        amount: u64,
        vault_owner: address // specifies against which vault player wants to bet
    ) acquires Vault {

        let player_address = signer::address_of(player);
        let coin_name = type_info::type_name<CoinType>();

        // check vault exists
        assert!(exists<Vault>(vault_owner), error::not_found(1));
        let vault = borrow_global_mut<Vault>(vault_owner);

        let from_balance: u64 = coin::balance<CoinType>(signer::address_of(player));
        assert!( amount <= from_balance, error::resource_exhausted(2));

        let (vault_rsrc_acc_signer, vault_rsrc_acc_addr) = get_rsrc_acc(vault);

        // 50% chance to win
        let flip_result = randomness::u64_range(0, 2);

        let fee_multiplier = fixed_point32::create_from_rational(10000 + FLIP_FEE_BPS, 10000);
        let amount_with_fees = multiply_u64(amount, fee_multiplier);

        // transfer bet amount + fees to the vault
        coin::transfer<CoinType>(player, vault_rsrc_acc_addr, amount_with_fees);

        if (flip_result == 1) {
            emit(FlipEventV2 {
                player: player_address,
                is_won: true,
                coin_name,
                amount_bet: amount
                });
            
            // double bet amount
            let payout = amount * FLIP_MULTIPLIER;

            // rewards player
            coin::transfer<CoinType>(
                &vault_rsrc_acc_signer,
                player_address,
                payout);

        } else {
            emit(FlipEventV2 {
                player: player_address,
                is_won: false,
                coin_name,
                amount_bet: amount
                });
        };
    }

    #[event]
    struct FlipEventV2 has drop, store {
        player: address,
        is_won: bool,
        coin_name: String,
        amount_bet: u64
    }

    ///////
    // Delegate Vault
    const FEE_RECEIVER: address = @0x9ee4495a9a76be1993c68fce69bdd06283b52c6305497c05305bae0598aaed08;
    const DELEGATE_FEE_BPS: u64 = 125;

    // treasury that players can play against
    struct DelegateVault has key, store {
        vault_address: account::SignerCapability,
    }

    public entry fun create_delegate_vault(
        deployer: &signer
    ) {
        // check wallet doesn't already have a vault
        assert!(!exists<DelegateVault>(signer::address_of(deployer)), error::not_found(0));

        // acquire a signer for the resource account that stores the coins
        let (_, vault_address) = account::create_resource_account(deployer, vector::empty());
        let rsrc_acc_signer  = account::create_signer_with_capability(&vault_address);

        // initialize an AptosCoin coin store there, which is where the vault APT will be kept
        coin::register<AptosCoin>(&rsrc_acc_signer);

        move_to(deployer, DelegateVault {
            vault_address,
        })
    }

    // Coin Agnostic Withdraw Function for the Delegate Vault
    public entry fun withdraw_coins_delegate<CoinType>(
        owner: &signer,
        amount: u64
    ) acquires DelegateVault {
        let owner_address = signer::address_of(owner);

        // only vault owner can withdraw from his vault
        assert!(exists<DelegateVault>(owner_address), error::not_found(3));

        let vault = borrow_global_mut<DelegateVault>(owner_address);

        let (rsrc_acc_signer, _) = get_rsrc_acc_d(vault);

        coin::transfer<CoinType>(
            &rsrc_acc_signer,
            owner_address,
            amount);
    }

    // Coin Agnostic Play Function for the Delegate Vault
    #[randomness]
    entry fun play_V3<CoinType>(
        player: &signer,
        amount: u64,
        vault_owner: address // specifies against which vault player wants to bet
    ) acquires DelegateVault {

        let player_address = signer::address_of(player);
        let coin_name = type_info::type_name<CoinType>();

        // check vault exists
        assert!(exists<DelegateVault>(vault_owner), error::not_found(1));
        let vault = borrow_global_mut<DelegateVault>(vault_owner);

        let from_balance: u64 = coin::balance<CoinType>(signer::address_of(player));
        assert!( amount <= from_balance, error::resource_exhausted(2));

        let (vault_rsrc_acc_signer, vault_rsrc_acc_addr) = get_rsrc_acc_d(vault);

        // 50% chance to win
        let flip_result = randomness::u64_range(0, 2);

        let delegate_fee_multiplier = fixed_point32::create_from_rational(10000 + DELEGATE_FEE_BPS, 10000);
        let amount_with_fees = multiply_u64(amount, delegate_fee_multiplier);

        let receiver_fee_multiplier = fixed_point32::create_from_rational(DELEGATE_FEE_BPS, 10000);
        let receiver_fees = multiply_u64(amount, receiver_fee_multiplier);

        // transfer bet amount to the vault
        coin::transfer<CoinType>(player, vault_rsrc_acc_addr, amount_with_fees);

        // transfer fees to the receiver
        coin::transfer<CoinType>(player, FEE_RECEIVER, receiver_fees);

        if (flip_result == 1) {
            emit(FlipEventV2 {
                player: player_address,
                is_won: true,
                coin_name,
                amount_bet: amount
                });
            
            // double bet amount
            let payout = amount * FLIP_MULTIPLIER;

            // rewards player
            coin::transfer<CoinType>(
                &vault_rsrc_acc_signer,
                player_address,
                payout);

        } else {
            emit(FlipEventV2 {
                player: player_address,
                is_won: false,
                coin_name,
                amount_bet: amount
                });
        };
    }

    // External Functions for other friend game modules
    friend fliptos::roulette;

    public(friend) fun transfer<CoinType>(
        amount: u64,
        vault_owner: address,
        player: address
    ) acquires Vault{
        assert!(exists<Vault>(vault_owner), error::not_found(1));
        let vault = borrow_global_mut<Vault>(vault_owner);
        let (vault_rsrc_acc_signer, _vault_rsrc_acc_addr) = get_rsrc_acc(vault);

        // rewards player
        coin::transfer<CoinType>(
            &vault_rsrc_acc_signer,
            player,
            amount);
    }


    // Internal Functions
    fun get_rsrc_acc(vault: &Vault): (signer, address) {

        let rsrc_acc_signer = account::create_signer_with_capability(&vault.vault_address);
        let rsrc_acc_address = signer::address_of(&rsrc_acc_signer);

        (rsrc_acc_signer, rsrc_acc_address)
    }

    fun get_rsrc_acc_d(vault: &DelegateVault): (signer, address) {

        let rsrc_acc_signer = account::create_signer_with_capability(&vault.vault_address);
        let rsrc_acc_address = signer::address_of(&rsrc_acc_signer);

        (rsrc_acc_signer, rsrc_acc_address)
    }

    /// Errors
    /// Vault already created
    const E_VAULT_ALREADY_CREATED: u8 = 0;
    /// Vault not found
    const E_VAULT_NOT_FOUND: u8 = 1;
    /// Not enough coins
    const E_NOT_ENOUGH_COINS: u8 = 2;
    /// Not vault owner
    const E_NOT_VAULT_OWNER: u8 = 3;
    /// Bet amount too high
    const E_MAX_BET_REACHED: u8 = 4;
}
