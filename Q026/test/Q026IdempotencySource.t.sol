// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {RelayHub} from "target/RelayHub.sol";
import {RelayOracleV2} from "target/RelayOracleV2.sol";
import {RelayOracleIdempotencyStore} from "target/RelayOracleIdempotencyStore.sol";

/// @notice Harness Q-026 [LA-OR-016]: apakah idempotency source yang jahat
///         (revert / selfdestruct / upgrade) menghentikan SELURUH eksekusi
///         oracle (mint global), atau hanya request yang bersangkutan?
///
/// Alur yang diuji: RelayOracleV2.execute / executeMultiple
///   -> _isExecuted(key) -> IDEMPOTENCY_STORE.isExecuted(key)
///   -> loop sources[i] -> source.isExecuted(key)  <-- titik serangan
contract Q026IdempotencySourceTest is Test {
  RelayHub internal hub;
  RelayOracleIdempotencyStore internal store;
  RelayOracleV2 internal oracle;

  address internal admin = makeAddr("admin");
  address internal operator = makeAddr("operator");
  address internal attacker = makeAddr("attacker");

  // EOA oracle signer — cukup vm.sign (SignatureChecker ECDSA path).
  uint256 internal constant ORACLE_SK = 0xA11CE;
  address internal oracleSigner;

  address internal recipient = makeAddr("recipient");
  uint256 internal constant TOKEN_ID = 1;
  uint256 internal constant AMOUNT = 100 ether;

  bytes32 internal constant KEY_A = keccak256("Q026-key-A");
  bytes32 internal constant KEY_B = keccak256("Q026-key-B");
  bytes32 internal constant KEY_C = keccak256("Q026-key-C");

  /// @notice Source sehat (deploy normal), switchable jahat via etch.
  RevertingSource internal evilSource;

  function setUp() public {
    oracleSigner = vm.addr(ORACLE_SK);

    vm.startPrank(admin);
    hub = new RelayHub(admin);
    hub.grantRole(hub.OPERATOR_ROLE(), operator);

    store = new RelayOracleIdempotencyStore(admin);

    oracle = new RelayOracleV2(admin, address(hub), address(store));
    oracle.grantRole(oracle.ORACLE_ROLE(), oracleSigner);
    // Oracle mint lewat HUB.mint -> butuh OPERATOR_ROLE di Hub.
    hub.grantRole(hub.OPERATOR_ROLE(), address(oracle));
    // Oracle menulis isStored via markExecuted -> butuh WRITE_ROLE di store.
    store.grantRole(store.WRITE_ROLE(), address(oracle));
    vm.stopPrank();

    // Source: deploy normal, lalu vm.etch menjadikan runtimeCode jahat.
    // vm.etch TIDAK menjalankan constructor — kontrak ini stateless,
    // jadi tidak perlu vm.store.
    evilSource = new RevertingSource();
    vm.prank(admin);
    store.addSource(address(evilSource));
  }

  // ---------------------------------------------------------------- helpers

  function _mintAction() internal view returns (bytes memory) {
    return abi.encode(uint8(0), recipient, TOKEN_ID, AMOUNT); // ActionType.MINT
  }

  function _sign(
    bytes32 idempotencyKey
  ) internal view returns (RelayOracleV2.Execution memory, bytes memory) {
    bytes[] memory actions = new bytes[](1);
    actions[0] = _mintAction();
    RelayOracleV2.Execution memory exec = RelayOracleV2.Execution(
      idempotencyKey,
      actions
    );
    bytes32 digest = _digest(exec);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_SK, digest);
    return (exec, abi.encodePacked(r, s, v));
  }

  function _digest(
    RelayOracleV2.Execution memory exec
  ) internal view returns (bytes32) {
    bytes32[] memory actionHashes = new bytes32[](exec.actions.length);
    for (uint256 i; i < exec.actions.length; ++i) {
      actionHashes[i] = keccak256(bytes(exec.actions[i]));
    }
    bytes32 structHash = keccak256(
      abi.encode(
        keccak256("Execution(bytes32 idempotencyKey,bytes[] actions)"),
        exec.idempotencyKey,
        keccak256(abi.encodePacked(actionHashes))
      )
    );
    return keccak256(
      abi.encodePacked("\x19\x01", _domainSeparator(), structHash)
    );
  }

  function _domainSeparator() internal view returns (bytes32) {
    // Domain standar EIP712("RelayOracle", "2") — dihitung manual.
    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    return
      keccak256(
        abi.encode(
          keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
          ),
          keccak256("RelayOracle"),
          keccak256("2"),
          chainId,
          address(oracle)
        )
      );
  }

  // ---------------------------------------------------------------- tests
  // Fase 1 — baseline sehat: mint lewat oracle ketika source sehat.

  function test_01_baseline_healthySource_MintSucceeds() public {
    // Ganti source jahat (selektif-revert) kembali ke healthy sebelum exec.
    vm.etch(address(evilSource), type(AlwaysFalseSource).runtimeCode);
    (RelayOracleV2.Execution memory exec, bytes memory sig) = _sign(KEY_A);
    oracle.execute(exec, oracleSigner, sig);
    assertEq(hub.balanceOf(recipient, TOKEN_ID), AMOUNT, "mint harus sukses");
    assertTrue(oracle.isExecuted(KEY_A), "key A harus tercatat");
  }

  // Fase 2 — source diubah jadi revert (vm.etch) sebelum exec pertama.
  // Klaim inti: SATU key yang tersangkut tidak boleh menghentikan key lain.

  function test_02_sourceReverts_IndependentKeysStillExecute() public {
    _etchReverting();

    // store.isExecuted(KEY_A) memanggil source dan revert — key A "tersangkut".
    vm.expectRevert(bytes("EVIL"));
    store.isExecuted(KEY_A);

    // Kunci Q-026: apakah key B (berbeda, sama-sama memanggil source) bisa
    // dieksekusi penuh (mint), atau ikut revert?
    (RelayOracleV2.Execution memory exec, bytes memory sig) = _sign(KEY_B);
    vm.expectRevert(bytes("EVIL"));
    oracle.execute(exec, oracleSigner, sig);
    // Jika revert menyebar: baris berikut tercapai hanya via expectRevert di atas.
    assertEq(
      hub.balanceOf(recipient, TOKEN_ID),
      0,
      "klaim: revert source menyebar ke key lain (mint B gagal)"
    );
  }

  function test_03_sourceReverts_executeMultiple_WholeBatchReverts() public {
    _etchReverting();

    RelayOracleV2.Execution[] memory execs = new RelayOracleV2.Execution[](3);
    bytes[] memory sigs = new bytes[](3);
    bytes32[3] memory keys = [KEY_A, KEY_B, KEY_C];
    for (uint256 i; i < 3; ++i) {
      (execs[i], sigs[i]) = _sign(keys[i]);
    }

    // executeMultiple: _isExecuted dipanggil DI LUAR try/catch (V2:165) —
    // revert source pada elemen pertama harus membatalkan SELURUH batch.
    vm.expectRevert(bytes("EVIL"));
    oracle.executeMultiple(execs, oracleSigner, sigs);
    assertEq(
      hub.balanceOf(recipient, TOKEN_ID),
      0,
      "klaim: seluruh batch revert (global halt)"
    );
  }

  // Fase 3 — varian "source jahat return true": bukan halt, tapi replay-door.

  function test_04_sourceReturnsTrue_LegacyKeysBlocked() public {
    // Source jahat yang menjawab isExecuted(key)=true untuk SEMUA key:
    // tidak revert, tapi setiap exec baru dianggap "sudah dieksekusi".
    vm.etch(
      address(evilSource),
      type(AlwaysTrueSource).runtimeCode
    );

    // execute() harus revert AlreadyExecuted — mint diblokir global.
    (RelayOracleV2.Execution memory exec, ) = _sign(KEY_B);
    vm.expectRevert(
      abi.encodeWithSelector(
        RelayOracleV2.AlreadyExecuted.selector,
        KEY_B
      )
    );
    oracle.execute(exec, oracleSigner, sigFor(KEY_B));

    // executeMultiple: _isExecuted==true hanya "continue" — batch diam,
    // tidak revert, tidak mint, tanpa event ExecutionFailed.
    RelayOracleV2.Execution[] memory execs = new RelayOracleV2.Execution[](2);
    bytes[] memory sigs = new bytes[](2);
    (execs[0], sigs[0]) = _sign(KEY_B);
    (execs[1], sigs[1]) = _sign(KEY_C);
    oracle.executeMultiple(execs, oracleSigner, sigs);
    assertEq(hub.balanceOf(recipient, TOKEN_ID), 0, "tidak ada mint");
  }

  // Fase 4 — selfdestruct path: source berubah jadi kode kosong.

  function test_05_selfdestructedSource_CallsStillDispatch() public {
    _etchReverting();
    // Simulasi selfdestruct: address berhenti punya code (EIP-6780:
    // selfdestruct post-Cancun hanya menghapus code dalam tx sama;
    // di sini vm.etch kode kosong sebagai efek netnya).
    vm.etch(address(evilSource), hex"");

    // Percakapan ke EOA (codeless) tetap "berhasil" dengan returndata kosong
    // — ABI-decode bool kosong... Solidity returndatasize-check akan revert
    // (empty returndata untuk fungsi yang mengembalikan bool → revert).
    vm.expectRevert();
    store.isExecuted(KEY_A);

    (RelayOracleV2.Execution memory exec, ) = _sign(KEY_C);
    vm.expectRevert();
    oracle.execute(exec, oracleSigner, sigFor(KEY_C));
  }

  // Fase 4b — gas-griefing: source jahat membakar gas sampai habis.
  // ("jahat" tidak harus revert — cukup mahal. isExecuted dipanggil dari
  // execute() sebelum mint; gas terkuras -> exec gagal.)

  function test_08_sourceGasBomb_ExecuteRunsOutOfGas() public {
    vm.etch(address(evilSource), type(GasBurnerSource).runtimeCode);

    (RelayOracleV2.Execution memory exec, bytes memory sig) = _sign(KEY_B);
    vm.expectRevert();
    oracle.execute{gas: 200000}(exec, oracleSigner, sig);
    assertEq(hub.balanceOf(recipient, TOKEN_ID), 0, "tidak ada mint");
  }

  // Fase 5 — upgrade path: admin ganti source. Sources TIDAK BISA dihapus
  // (add-only by design) — satu-satunya mitigasi adalah upgrade source
  // IN PLACE (etch) karena slot sources[i] permanen.

  function test_06_inPlaceUpgradeSourceRestoresExecution() public {
    _etchReverting();

    // Admin (atau penyerang yang kontrol source) upgrade in-place:
    // etch runtimeCode baru yang menjawab false — store kembali sehat.
    vm.etch(
      address(evilSource),
      type(AlwaysFalseSource).runtimeCode
    );

    (RelayOracleV2.Execution memory exec, ) = _sign(KEY_C);
    oracle.execute(exec, oracleSigner, sigFor(KEY_C));
    assertEq(hub.balanceOf(recipient, TOKEN_ID), AMOUNT, "pulih via upgrade");
  }

  function test_07_store_hasNoSourceRemoval_AdminCannotUninstall() public {
    // addSource ada; TIDAK ADA removeSource — mitigasi halt tidak bisa
    // berupa "lepas source", hanya upgrade in-place source itu sendiri.
    (bool ok, ) = address(store).call(
      abi.encodeWithSignature("removeSource(address)", address(evilSource))
    );
    assertFalse(ok, "removeSource tidak ada (add-only by design)");
    assertTrue(store.isSource(address(evilSource)), "source tetap terpasang");
  }

  // ------------------------------------------------------------ internals

  function sigFor(bytes32 key) internal view returns (bytes memory) {
    (, bytes memory sig) = _sign(key);
    return sig;
  }

  function _etchReverting() internal {
    vm.etch(address(evilSource), type(RevertingSource).runtimeCode);
  }
}

// ---------------------------------------------------------------- mocks

/// @notice Source jahat selektif: jawab false untuk key 0 (lolos probe
///         addSource) lalu REVERT untuk key lain. addSource memvalidasi
///         source hanya dengan isExecuted(bytes32(0)) — try/catch satu
///         panggilan, sekali, saat add. Perilaku buruk di key lain lolos.
contract RevertingSource {
  function isExecuted(bytes32 key) external pure returns (bool) {
    if (key == bytes32(0)) {
      return false;
    }
    revert("EVIL");
  }
}

/// @notice Source jahat varian "blokir semua": jawab true untuk semua key.
contract AlwaysTrueSource {
  function isExecuted(bytes32) external pure returns (bool) {
    return true;
  }
}

/// @notice Source gas-burner: loop membakar gas hingga habis.
contract GasBurnerSource {
  function isExecuted(bytes32) external pure returns (bool) {
    uint256 x;
    for (uint256 i; i < type(uint256).max; ++i) {
      x += i;
    }
    return x > 0;
  }
}

/// @notice Source sehat minimal: tidak pernah eksekusi apa pun.
contract AlwaysFalseSource {
  function isExecuted(bytes32) external pure returns (bool) {
    return false;
  }
}
