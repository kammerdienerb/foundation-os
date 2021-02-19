#include <efi.h>
#include <efilib.h>

#define u8    uint8_t
#define u16   uint16_t
#define u32   uint32_t
#define u64   uint64_t
#define uSIZE UINTN

#define s8    int8_t
#define s16   int16_t
#define s32   int32_t
#define s64   int64_t
#define sSIZE INTN

#define CLS()            (ST->ConOut->ClearScreen(ST->ConOut))
#define PUTS(s)          (ST->ConOut->OutputString(ST->ConOut, L##s))
#define GET_KEY(key_ptr) (ST->ConIn->ReadKeyStroke(ST->ConIn, (key_ptr)))
#define SLEEP(s)         (BS->Stall((s) * 1000000))
#define MSLEEP(s)        (BS->Stall((s) * 1000))

/* NOTE: @bad -- assuming little-endianess */

static void put_unsigned(u64 u) {
    CHAR16  buff[64];
    CHAR16 *p;

    buff[63] = 0;
    p        = buff + 62;

    do {
        *p  = L'0' + u % 10;
        p  -= 1;
        u  /= 10;
    } while (u);

    ST->ConOut->OutputString(ST->ConOut, p + 1);
}

static void put_hex(u64 u) {
    CHAR16 *digits;
    CHAR16  buff[64];
    CHAR16 *p;

    digits = L"0123456789ABCDEF";

    buff[63] = 0;
    p        = buff + 62;

    do {
        *p   = digits[u & 0xF];
        p   -= 1;
        u  >>= 4;
    } while (u);

    *p = L'x';
    p -= 1;
    *p = L'0';

    ST->ConOut->OutputString(ST->ConOut, p);
}

static void put_signed(s64 s) {
    CHAR16  buff[64];
    CHAR16 *p;
    u32     is_neg;

    buff[63] = 0;
    p        = buff + 62;
    is_neg   = s < 0;

    if (is_neg) { s = 0 - s; }

    do {
        *p  = L'0' + s % 10;
        p  -= 1;
        s  /= 10;
    } while (s);

    if (is_neg) {
        *p  = L'-';
        p  -= 1;
    }

    ST->ConOut->OutputString(ST->ConOut, p + 1);
}

static void _vprintf(CHAR16 *fmt, va_list args) {
    CHAR16  c;
    CHAR16 *run_start;
    u64     u;
    s64     d;
    CHAR16 *s;

    run_start = fmt;

    while ((c = *fmt)) {
        if (c == L'%') {
            if (!*(fmt + 1)) {
                fmt += 1;
                break;
            }

            *fmt  = L'\0';
            ST->ConOut->OutputString(ST->ConOut, run_start);
            *fmt  = c;
            fmt  += 1;

            switch (*fmt) {
                case L'u':
                    u = va_arg(args, u64);
                    put_unsigned(u);
                    break;
                case L'x':
                    u = va_arg(args, u64);
                    put_hex(u);
                    break;
                case L'd':
                    d = va_arg(args, s64);
                    put_signed(d);
                    break;
                case L's':
                    s = va_arg(args, CHAR16*);
                    ST->ConOut->OutputString(ST->ConOut, s);
                    break;
                case L'%':
                    run_start = fmt;
                    goto next;
                default:
                    fmt -= 1;
            }
            fmt += 1;

            run_start = fmt;
        } else {
next:;
            fmt  += 1;
        }
    }

    if (run_start < fmt) {
        ST->ConOut->OutputString(ST->ConOut, run_start);
    }
}

static void _printf(CHAR16 *fmt, ...) {
    va_list args;

    va_start(args, fmt);
    _vprintf(fmt, args);
    va_end(args);
}

#define PRINTF(s, ...) (_printf(L##s, ##__VA_ARGS__))

#define SUCCESS_OR_ERR(what, fmt, ...) \
do {                                   \
    status = (what);                   \
    if (EFI_ERROR(status)) {           \
        PRINTF(fmt, ##__VA_ARGS__);    \
        goto err;                      \
    }                                  \
} while (0)

static EFI_STATUS get_memory_map(void) {
    EFI_STATUS             status;
    uSIZE                  mem_map_buff_size;
    EFI_MEMORY_DESCRIPTOR *mem_map;
    uSIZE                  mem_map_key;
    uSIZE                  mem_map_descriptor_size;
    u32                    mem_map_descriptor_version;
    sSIZE                  i;
    EFI_MEMORY_DESCRIPTOR *mem_region;
    EFI_INPUT_KEY          key;

    status            = 0;
    mem_map_buff_size = 0;
    mem_map           = NULL;

    status = BS->GetMemoryMap(
                &mem_map_buff_size,
                mem_map,
                &mem_map_key,
                &mem_map_descriptor_size,
                &mem_map_descriptor_version);

    if (status != EFI_BUFFER_TOO_SMALL) {
        PRINTF("unexpected return code from GetMemoryMap() %x\r\n", status);
        goto err;
    }

    PRINTF("First call to GetMemoryMap():\r\n");
    PRINTF("    BUFF_SIZE    KEY    DESCRIPTOR_SIZE    DESCRIPTOR_VERSION\r\n");
    PRINTF("    %u         %u   %u                 %u\r\n",
           mem_map_buff_size, mem_map_key, mem_map_descriptor_size, mem_map_descriptor_version);

    PRINTF("Allocating a buffer for the memory map..\r\n");

    /*
    ** We need to add to the total buffer size to account for the extra
    ** memory regions created by allocating the buffer in the first place.
    ** Unless you just just add small amounts and call GetMemoryMap() in a
    ** loop, it seems like you just want to guess at a reasonable increase
    ** and do it.
    ** I saw someone online use this 2 * descriptor_size guess, so we'll go
    ** with that for now.
    */
    mem_map_buff_size += 2 * mem_map_descriptor_size;


    SUCCESS_OR_ERR(BS->AllocatePool(EfiLoaderData, mem_map_buff_size, (void*)&mem_map),
                   "Failed to allocate memory for the memory map.\r\n");

    PRINTF("    allocated a %u byte pool of memory type EfiLoaderData at %x\r\n",
           mem_map_buff_size, mem_map);

    SUCCESS_OR_ERR(BS->GetMemoryMap(
                    &mem_map_buff_size,
                    mem_map,
                    &mem_map_key,
                    &mem_map_descriptor_size,
                    &mem_map_descriptor_version),
                  "Second call to GetMemoryMap() failed\r\n");

    PRINTF("Second call to GetMemoryMap():\r\n");
    PRINTF("    BUFF_SIZE    KEY    DESCRIPTOR_SIZE    DESCRIPTOR_VERSION\r\n");
    PRINTF("    %u         %u   %u                 %u\r\n",
           mem_map_buff_size, mem_map_key, mem_map_descriptor_size, mem_map_descriptor_version);

    PRINTF("\r\n========================= MEMORY MAP =========================\r\n");
    for (i = 0; i < mem_map_buff_size; i += mem_map_descriptor_size) {
        mem_region = (EFI_MEMORY_DESCRIPTOR*)(((void*)mem_map) + i);

        PRINTF("%x - %x: ",
               mem_region->PhysicalStart,
               mem_region->PhysicalStart + (EFI_PAGE_SIZE * mem_region->NumberOfPages));
        switch (mem_region->Type) {
            case EfiReservedMemoryType:      PRINTF("ReservedMemoryType      "); break;
            case EfiLoaderCode:              PRINTF("LoaderCode              "); break;
            case EfiLoaderData:              PRINTF("LoaderData              "); break;
            case EfiBootServicesCode:        PRINTF("BootServicesCode        "); break;
            case EfiBootServicesData:        PRINTF("BootServicesData        "); break;
            case EfiRuntimeServicesCode:     PRINTF("RuntimeServicesCode     "); break;
            case EfiRuntimeServicesData:     PRINTF("RuntimeServicesData     "); break;
            case EfiConventionalMemory:      PRINTF("ConventionalMemory      "); break;
            case EfiUnusableMemory:          PRINTF("UnusableMemory          "); break;
            case EfiACPIReclaimMemory:       PRINTF("ACPIReclaimMemory       "); break;
            case EfiACPIMemoryNVS:           PRINTF("ACPIMemoryNVS           "); break;
            case EfiMemoryMappedIO:          PRINTF("MemoryMappedIO          "); break;
            case EfiMemoryMappedIOPortSpace: PRINTF("MemoryMappedIOPortSpace "); break;
            case EfiPalCode:                 PRINTF("PalCode                 "); break;
            default:                         PRINTF("??? ");
        }

        PRINTF("attr: %x", mem_region->Attribute);
        PRINTF("\r\n");

/*         if (i % 10 == 0 && i > 0) { */
/*             PRINTF("[ PRESS ANY KEY TO SEE MORE MEMORY MAP ENTRIES ]"); */
/*             while ((status = GET_KEY(&key)) == EFI_NOT_READY) { MSLEEP(100); } */
/*             PRINTF("\r                                                   \r"); */
/*         } */
    }
    PRINTF("==============================================================\r\n");


err:;
out:;
    return status;
}

static s32 guid_equ(EFI_GUID *a, EFI_GUID *b) {
    return    a->Data1 == b->Data1
           && a->Data2 == b->Data2
           && a->Data3 == b->Data3
           && (  a->Data4[0] == b->Data4[0]
              && a->Data4[1] == b->Data4[1]
              && a->Data4[2] == b->Data4[2]
              && a->Data4[3] == b->Data4[3]
              && a->Data4[4] == b->Data4[4]
              && a->Data4[5] == b->Data4[5]
              && a->Data4[6] == b->Data4[6]
              && a->Data4[7] == b->Data4[7]);
}

struct RSDPDescriptor {
    char     Signature[8];
    uint8_t  Checksum;
    char     OEMID[6];
    uint8_t  Revision;
    uint32_t RsdtAddress;
} __attribute__ ((packed));

struct RSDPDescriptor20 {
    struct RSDPDescriptor firstPart;

    uint32_t              Length;
    uint64_t              XsdtAddress;
    uint8_t               ExtendedChecksum;
    uint8_t               reserved[3];
} __attribute__ ((packed));

struct ACPISDTHeader {
  char     Signature[4];
  uint32_t Length;
  uint8_t  Revision;
  uint8_t  Checksum;
  char     OEMID[6];
  char     OEMTableID[8];
  uint32_t OEMRevision;
  uint32_t CreatorID;
  uint32_t CreatorRevision;
};

static EFI_STATUS get_acpi_tables(void) {
    EFI_STATUS               status;
    EFI_GUID                 acpi_guid;
    EFI_GUID                 acpi2_guid;
    void                    *vrsdpd;
    void                    *vrsdpd2;
    struct RSDPDescriptor   *rsdpd;
    struct RSDPDescriptor20 *rsdpd2;
    uSIZE                    i;
    EFI_CONFIGURATION_TABLE *config_table;
    CHAR16                   sig16[9];
    CHAR16                   oemid16[7];
    struct ACPISDTHeader    *root_table_header;
    struct ACPISDTHeader    *table_header;

    PRINTF("\r\nAttempting to acquire ACPI tables..\r\n");

    status     = 0;
    acpi_guid  = (EFI_GUID)ACPI_TABLE_GUID;
    acpi2_guid = (EFI_GUID)ACPI_20_TABLE_GUID;
    vrsdpd     = NULL;
    vrsdpd2    = NULL;
    rsdpd      = NULL;
    rsdpd2     = NULL;

    for (i = 0; i < ST->NumberOfTableEntries; i += 1) {
        config_table = ST->ConfigurationTable + i;
        if (guid_equ(&config_table->VendorGuid, &acpi_guid)) {
            vrsdpd = config_table->VendorTable;
        } else if (guid_equ(&config_table->VendorGuid, &acpi2_guid)) {
            vrsdpd2 = config_table->VendorTable;
        }
    }

    if (vrsdpd == NULL && vrsdpd2 == NULL) {
        PRINTF("Could not find ACPI Root System Description Table.\r\n");
        status = EFI_NOT_FOUND;
        goto err;
    }

    rsdpd  = vrsdpd;
    rsdpd2 = vrsdpd2;

    /* @todo -- checksum */

    sig16[8] = 0;
    for (i = 0; i < 8; i += 1) { sig16[i] = (CHAR16)rsdpd->Signature[i]; }

    oemid16[6] = 0;
    for (i = 0; i < 6; i += 1) { oemid16[i] = (CHAR16)rsdpd->OEMID[i]; }

    root_table_header = (void*)(rsdpd->Revision ? rsdpd2->XsdtAddress : rsdpd->RsdtAddress);

    PRINTF("============================ ACPI ============================\r\n");
    PRINTF("    Signature:     '%s'\r\n", sig16);
    PRINTF("    OEM ID:        '%s'\r\n", oemid16);
    PRINTF("    ACPI Revision: %u\r\n", rsdpd->Revision);
    PRINTF("    %s address:  %x\r\n", rsdpd->Revision ? L"XSDT" : L"RSDT", (void*)root_table_header);

    for (i = 0; i < root_table_header->Length; i += 1) {
        table_header = ((void*)root_table_header) + sizeof(struct ACPISDTHeader) + (i * sizeof(uSIZE));
        PRINTF("    TABLE: %x\r\n", (void*)table_header);
    }

    PRINTF("==============================================================\r\n");
err:;
out:;
    return status;
}

EFI_STATUS uefi_loader_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable) {
    EFI_STATUS    status;
    EFI_INPUT_KEY key;

    ST = SystemTable;
    BS = ST->BootServices;

    CLS();

    PRINTF("Loading Foundation OS...\r\n");

    SUCCESS_OR_ERR(ST->ConIn->Reset(ST->ConIn, FALSE), "failed to reset console\r\n");
    SUCCESS_OR_ERR(get_memory_map(), "get_memory_map() failed\r\n");
    SUCCESS_OR_ERR(get_acpi_tables(), "get_acpi_tables() failed\r\n");

    PRINTF("Success!\r\n");

    goto out;

err:;
    PRINTF("The booloader encoutered an error (status = %x).. aborting.\r\n", status);

out:;
    PRINTF("[ PRESS ANY KEY TO EXIT TO FIRMWARE ]");
    while ((status = GET_KEY(&key)) == EFI_NOT_READY) { SLEEP(1); }

    return status;
}
