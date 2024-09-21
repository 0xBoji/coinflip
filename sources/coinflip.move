module fliptos::coinflip {
    // === Imports ===
    use std::error;
    use std::signer;
    use std::vector;
    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::randomness;
    use 0x1::fixed_point32::multiply_u64;
    use 0x1::fixed_point32;
    use 0x1::aptos_coin::AptosCoin;
    use 0x1::event::emit;

    // === Errors ===
    /// Vault already created

    const E_VAULT_ALREADY_CREATED: u8 = 0;
    /// Vault not found
    const E_VAULT_NOT_FOUND: u8 = 1;
    /// Not enough coins
    const E_NOT_ENOUGH_COINS: u8 = 2;
    /// Not vault owner
    const E_NOT_VAULT_OWNER: u8 = 3;

    // === Constants ===

    const FLIP_MULTIPLIER: u64 = 2;
    const FLIP_FEE_BPS: u64 = 250;

    // === Structs ===
    // treasury that players can play against
    struct Vault has key, store {

        vault_address: account::SignerCapability,
    }

    // === Events ===
    #[event]
    struct FlipEvent has drop, store {

        player: address,
        is_won: bool,
        amount_bet: u64
    }

    // === Entry Functions ===
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

    // === Flip Functions ===
    #[randomness]
    entry fun play(
        player: &signer,
        amount: u64,
        vault_owner: address // specifies against which vault player wants to bet
    ) acquires Vault {

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

    // Internal Functions
    fun get_rsrc_acc(vault: &Vault): (signer, address) {

        let rsrc_acc_signer = account::create_signer_with_capability(&vault.vault_address);
        let rsrc_acc_address = signer::address_of(&rsrc_acc_signer);

        (rsrc_acc_signer, rsrc_acc_address)
    }


}