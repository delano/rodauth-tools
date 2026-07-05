# lib/rodauth/tools/account_id_cipher.rb
#
# frozen_string_literal: true

require 'openssl'

module Rodauth
  module Tools
    # Keyed format-preserving obfuscator for integer primary keys.
    #
    # Turns a numeric account id (e.g. +2+) into a fixed-width, URL-safe,
    # non-sequential token (e.g. +"E946V4SD7Z7RV"+) and back again, WITHOUT
    # changing the database schema. The mapping is a keyed pseudo-random
    # permutation (a bijection) over the 64-bit domain, so:
    #
    # - every id maps to exactly one token and vice-versa (no collisions),
    # - the token reveals nothing about the id or about neighbouring ids
    #   to anyone who does not hold the secret,
    # - +decode(encode(id)) == id+ for all ids in range, and +decode+ rejects
    #   any well-formed-but-non-canonical token (see {#decode}).
    #
    # It is a 4-round Feistel network keyed with HMAC-SHA256. This is genuine
    # keyed encryption over a small domain (format-preserving encryption),
    # not a reversible "encoder" like Hashids/Sqids: without the secret the
    # permutation is hard to invert and, for a bounded number of observed
    # tokens, hard to distinguish from random. As with any small-block Feistel
    # construction, that only holds up to the birthday bound of the 32-bit
    # half-block (roughly 2^16 tokens observed under one secret) — it is not
    # an unconditional guarantee at unbounded query volume.
    #
    # The output alphabet is Crockford Base32, which deliberately excludes the
    # +_+ character so encoded ids never collide with Rodauth's +token_separator+.
    #
    # This class is a pure +Integer <-> 13-char+ bijection: it knows nothing
    # about versions, prefixes or legacy formats. The +account_id_obfuscation+
    # feature adds a one-character non-digit version prefix on top (which is what
    # makes obfuscated tokens deterministically distinguishable from legacy
    # decimal ids and drives key rotation), keeping this primitive reusable and
    # trivially testable in isolation.
    #
    # @example
    #   cipher = Rodauth::Tools::AccountIdCipher.new(ENV.fetch('ACCOUNT_ID_SECRET'))
    #   token  = cipher.encode(2)     # => "E946V4SD7Z7RV" (13 chars)
    #   cipher.decode(token)          # => 2
    #   cipher.decode('not-a-token')  # => nil
    class AccountIdCipher
      MASK32 = 0xFFFF_FFFF
      MASK64 = 0xFFFF_FFFF_FFFF_FFFF
      ROUNDS = 4

      # Crockford Base32 (no I, L, O, U; no underscore). 13 chars encodes 65 bits,
      # covering the full 64-bit domain with a fixed, padding-free width.
      ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
      WIDTH = 13

      # Minimum secret length. HMAC-SHA256's block size is 64 bytes; 32 bytes
      # (256 bits) is the smallest key we accept as cryptographically adequate.
      MIN_SECRET_BYTES = 32

      # @param secret [String] a high-entropy key of at least 32 bytes. Keep this
      #   independent of +hmac_secret+ so rotating the HMAC secret does not
      #   invalidate in-flight obfuscated ids.
      # @raise [ArgumentError] if the secret is shorter than 32 bytes.
      def initialize(secret)
        secret = secret.to_s
        raise ArgumentError, "secret must be at least #{MIN_SECRET_BYTES} bytes" if secret.bytesize < MIN_SECRET_BYTES

        @secret = secret
      end

      # Encode an integer id into its fixed-width obfuscated token.
      #
      # @param id [Integer, String] the numeric account id, parsed with the
      #   strict Kernel#Integer — unlike #to_i, a non-integer String (or other
      #   value Integer() rejects) raises ArgumentError rather than silently
      #   truncating.
      # @return [String] a 13-character Crockford Base32 token
      def encode(id)
        base32(feistel(Integer(id) & MASK64, :encrypt))
      end

      # Decode an obfuscated token back into its integer id.
      #
      # Returns +nil+ for anything that is not a well-formed 13-char token (wrong
      # length, illegal character, non-string), so callers can pass foreign input
      # through without raising. Also returns +nil+ for a well-formed-but-
      # non-canonical token: 13 Crockford chars encode 65 bits for a 64-bit
      # block, so each id has exactly one canonical 13-char token but a second,
      # non-canonical encoding that differs only in the (discarded) 65th bit of
      # its first character. Re-encoding the decrypted id and comparing against
      # the input rejects that non-canonical form, keeping {#decode} a strict
      # inverse of {#encode} rather than a 2-to-1 mapping.
      #
      # @param token [String] a token previously produced by {#encode}
      # @return [Integer, nil] the original id, or nil if +token+ is not a
      #   valid, canonical token
      def decode(token)
        number = unbase32(token)
        return nil unless number

        id = feistel(number, :decrypt)
        encode(id) == token ? id : nil
      end

      private

      # 4-round Feistel network. Encryption runs the round schedule forward;
      # decryption runs it in reverse, which inverts the permutation exactly.
      def feistel(block, direction)
        left  = (block >> 32) & MASK32
        right = block & MASK32

        schedule = (0...ROUNDS).to_a
        schedule = schedule.reverse if direction == :decrypt

        schedule.each do |round_index|
          left, right = right, (left ^ round_function(round_index, right))
        end

        ((right << 32) | left) & MASK64
      end

      # Keyed round function: HMAC-SHA256 over the round index and half-block,
      # folded to 32 bits. Domain-separating on the round index keeps the
      # per-round subkeys independent.
      def round_function(round_index, half)
        digest = OpenSSL::HMAC.digest('SHA256', @secret, [round_index, half].pack('C N'))
        digest.unpack1('N')
      end

      # Little-endian Crockford Base32, fixed 13 chars.
      def base32(number)
        Array.new(WIDTH) { |i| ALPHABET[(number >> (5 * i)) & 31] }.reverse.join
      end

      # Inverse of {#base32}. Returns nil (never raises) on malformed input so
      # {#decode} can treat legacy/foreign values as "not one of ours".
      def unbase32(token)
        return nil unless token.is_a?(String) && token.length == WIDTH

        token.each_char.reduce(0) do |acc, char|
          value = ALPHABET.index(char)
          return nil unless value

          (acc << 5) | value
        end & MASK64
      end
    end
  end
end
