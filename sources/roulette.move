module fliptos::roulette {

    // Module for the Fliptos Roulette
    // Implements the Native Randomness for a provably fair game

    use std::error;
    use std::signer;
    use std::vector;
    use std::string::String;
    use aptos_framework::coin;
    use aptos_framework::randomness;
    use aptos_framework::math64;
    use 0x1::aptos_coin::AptosCoin;
    use 0x1::event::emit;
    use aptos_std::type_info;

    use fliptos::coinflip;

    const MAX_PAYOUT_APT: u64 = 2000_000_000;
    const VAULT: address = @0xb4b029bb113999850d806c44a487545e2f3f3ef9ae787d7dbf09df98e4a1249f;


    #[randomness]
    entry fun play<CoinType>(
        player: &signer,
        amount: u64,
        chosen_numbers: vector<u64>,
        vault_owner: address // specifies against which vault player wants to bet
    ) {
        let player_address = signer::address_of(player);
        let coin_name = type_info::type_name<CoinType>();
        let apt_name = type_info::type_name<AptosCoin>();

        let nb_chosen_numbers = vector::length<u64>(&chosen_numbers);
        
        let payout = math64::mul_div(amount, 36, nb_chosen_numbers);

        // check bet amount is below max for APT
        // Make it adaptable !!!
        if (coin_name == apt_name) {
            assert!(payout <= MAX_PAYOUT_APT, error::resource_exhausted(1));
        };
        
        // player can choose max 37 numbers
        assert!(nb_chosen_numbers <= 37, error::resource_exhausted(0));
    
        let roulette_outcome = randomness::u64_range(0, 37);

        // transfer bet amount to the vault
        coin::transfer<CoinType>(player, VAULT, amount);
        
        for (i in 0..nb_chosen_numbers) {
            let number = vector::borrow<u64>(&chosen_numbers, i);

            if (number == &roulette_outcome) {
                
                coinflip::transfer<CoinType>(payout, vault_owner, player_address);

                emit(RouletteEvent {
                    player: player_address,
                    is_won: true,
                    coin_name,
                    amount_bet: amount,
                    chosen_numbers,
                    roulette_outcome
                });
                return
            }; 
        };

        emit(RouletteEvent {
                    player: player_address,
                    is_won: false,
                    coin_name,
                    amount_bet: amount,
                    chosen_numbers,
                    roulette_outcome
                });

    }

    #[event]
    struct RouletteEvent has drop, store {
        player: address,
        is_won: bool,
        coin_name: String,
        amount_bet: u64,
        chosen_numbers: vector<u64>,
        roulette_outcome: u64
    }

    /// Errors
    /// Too many numbers chosen
    const E_TOO_MANY_NUMBERS: u8 = 0;
    /// Bet amount too high
    const E_MAX_BET_REACHED: u8 = 1;
}
