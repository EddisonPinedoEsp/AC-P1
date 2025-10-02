# Documentación de la ALU IEEE-754

## Descripción General

Esta implementación proporciona una Unidad Aritmético-Lógica (ALU) completa para operaciones en punto flotante IEEE-754, soportando tanto single precision (32 bits) como half precision (16 bits).

## Arquitectura del Sistema

### Módulo Principal: `alu.v`
- **Descripción**: Controlador principal que coordina todas las operaciones
- **Interfaz**: Máquina de estados que maneja el flujo de ejecución
- **Operaciones soportadas**: ADD, SUB, MUL, DIV

### Módulos Componentes

#### 1. `ieee754_decoder.v`
- **Función**: Decodifica números IEEE-754 en componentes (signo, exponente, mantisa)
- **Características**:
  - Detección automática de casos especiales (NaN, ±Inf, ceros, denormales)
  - Conversión entre formatos 16-bit y 32-bit
  - Normalización de exponentes con bias apropiado

#### 2. `fp_adder_subber.v`
- **Función**: Realiza operaciones de suma y resta
- **Algoritmo**:
  1. Alineación de exponentes
  2. Suma/resta de mantisas
  3. Normalización del resultado
  4. Detección de overflow/underflow

#### 3. `fp_multiplier.v`
- **Función**: Realiza multiplicación de punto flotante
- **Algoritmo**:
  1. XOR de signos
  2. Suma de exponentes
  3. Multiplicación de mantisas
  4. Normalización y redondeo

#### 4. `fp_divider.v`
- **Función**: Realiza división de punto flotante
- **Algoritmo**: División SRT (Sweeney, Robertson, Tocher) simplificada
- **Características**: Máquina de estados para división iterativa

#### 5. `ieee754_encoder.v`
- **Función**: Ensambla el resultado final en formato IEEE-754
- **Conversión**: Maneja conversión automática entre formatos 16-bit y 32-bit

## Especificaciones de la Interfaz

### Entradas
| Señal | Ancho | Descripción |
|-------|-------|-------------|
| `clk` | 1 | Reloj del sistema |
| `rst` | 1 | Reset síncrono |
| `op_a[31:0]` | 32 | Operando A (IEEE-754) |
| `op_b[31:0]` | 32 | Operando B (IEEE-754) |
| `op_code[2:0]` | 3 | Código de operación (000=ADD, 001=SUB, 010=MUL, 011=DIV) |
| `mode_fp` | 1 | Formato: 0=half precision (16-bit), 1=single precision (32-bit) |
| `round_mode[1:0]` | 2 | Modo de redondeo: 00=nearest even |
| `start` | 1 | Inicia la operación |

### Salidas
| Señal | Ancho | Descripción |
|-------|-------|-------------|
| `result[31:0]` | 32 | Resultado en formato IEEE-754 |
| `valid_out` | 1 | Indica resultado válido y listo |
| `flags[4:0]` | 5 | Flags de estado: [invalid, div_by_zero, overflow, underflow, inexact] |

## Formato de Datos IEEE-754

### Single Precision (32 bits)
```
Bit:    31  30-23   22-0
Campo:  S   E[7:0]  M[22:0]
Bias:   -   127     -
```

### Half Precision (16 bits)
```
Bit:    15  14-10   9-0
Campo:  S   E[4:0]  M[9:0]  
Bias:   -   15      -
```

## Casos Especiales Soportados

### NaN (Not a Number)
- **Single**: `0x7FC00000` (Quiet NaN)
- **Half**: `0x7E000000` (en bits [31:16])
- **Propagación**: Cualquier operación con NaN resulta en NaN

### Infinito
- **Single**: `0x7F800000` (+∞), `0xFF800000` (-∞)
- **Half**: `0x7C000000` (+∞), `0xFC000000` (-∞)
- **Operaciones**:
  - ∞ + número = ∞
  - ∞ - ∞ = NaN
  - ∞ × 0 = NaN
  - ∞ ÷ ∞ = NaN

### Ceros
- **Positivo**: `0x00000000`
- **Negativo**: `0x80000000`
- **Operaciones**: Manejo correcto del signo

### División por Cero
- `número ÷ 0 = ±∞` (flag divide_by_zero activo)
- `0 ÷ 0 = NaN` (flag invalid_operation activo)

## Modos de Redondeo

Actualmente implementado:
- **Round to Nearest Even (00)**: Redondeo por defecto IEEE-754

Preparado para implementar:
- **Round toward Zero (01)**
- **Round Up (10)**
- **Round Down (11)**

## Flags de Estado

| Bit | Nombre | Descripción |
|-----|--------|-------------|
| 4 | Invalid Operation | Operación produce NaN (0÷0, ∞-∞, √(-1)) |
| 3 | Divide by Zero | División de número finito por cero |
| 2 | Overflow | Resultado demasiado grande para representar |
| 1 | Underflow | Resultado demasiado pequeño (→ cero) |
| 0 | Inexact | Resultado fue redondeado |

## Máquina de Estados Principal

```
IDLE → DECODE → COMPUTE → NORMALIZE → ENCODE → DONE → IDLE
```

1. **IDLE**: Espera señal `start`
2. **DECODE**: Extrae componentes IEEE-754
3. **COMPUTE**: Ejecuta operación o maneja casos especiales
4. **NORMALIZE**: Ajusta resultado y detecta excepciones
5. **ENCODE**: Ensambla formato IEEE-754 final
6. **DONE**: Activa `valid_out`, espera `start=0`

## Rendimiento y Latencia

| Operación | Latencia (ciclos) | Notas |
|-----------|-------------------|-------|
| ADD/SUB | 6 | Incluye alineación y normalización |
| MUL | 4 | Multiplicación combinacional |
| DIV | 30-35 | División iterativa (24 bits) |

## Recursos FPGA Estimados (Basys3)

| Recurso | Utilizado | Disponible | Porcentaje |
|---------|-----------|------------|------------|
| LUTs | ~2500 | 20800 | ~12% |
| Flip-Flops | ~800 | 41600 | ~2% |
| DSP48E1 | 4-6 | 90 | ~7% |
| Block RAM | 0 | 50 | 0% |

## Testing y Verificación

### Testbench Básico (`alu_testbench.v`)
- Casos predefinidos importantes
- Verificación de casos especiales
- Pruebas de ambos formatos (16/32 bits)

### Testbench Avanzado (`alu_advanced_testbench.v`)
- 100+ casos aleatorios
- Verificación de propiedades matemáticas
- Estadísticas de éxito/fallo
- Detección de coherencia en resultados

### Casos de Prueba Incluidos
- Operaciones básicas: 1+1, 2-1, 2×0.5, 4÷2
- Casos especiales: NaN, ±∞, ±0
- Propiedades: Conmutatividad (a+b=b+a, a×b=b×a)
- Casos límite: Overflow, underflow, división por cero

## Instrucciones de Uso con Vivado

### 1. Crear Proyecto
```tcl
source ./Implementacion/create_vivado_project.tcl
```

### 2. Ejecutar Síntesis
```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
```

### 3. Implementación
```tcl
launch_runs impl_1 -jobs 4  
wait_on_run impl_1
```

### 4. Generar Bitstream
```tcl
launch_runs impl_1 -to_step write_bitstream -jobs 4
```

### 5. Programar FPGA
```tcl
open_hw_manager
connect_hw_server
open_hw_target
program_hw_devices [get_hw_devices xc7a35t_0]
```

## Configuración para Basys3

- **Clock**: 100 MHz (constraint automático)
- **Reset**: Botón central (U18)
- **LEDs**: Flags de estado (U16, E19, U19, V19, W18)
- **LED adicional**: Valid output (U15)

## Limitaciones Conocidas

1. **Redondeo**: Solo implementado "round to nearest even"
2. **Denormales**: Tratados como cero (simplificación)
3. **División**: Implementación iterativa (mayor latencia)
4. **Precisión**: Ligera pérdida en conversiones 16↔32 bits

## Mejoras Futuras Sugeridas

1. **Implementar todos los modos de redondeo**
2. **Soporte completo para números denormales**
3. **División hardware optimizada (Newton-Raphson)**
4. **Pipeline para mayor throughput**
5. **Soporte para operaciones fusionadas (FMA)**
6. **Optimización de área vs velocidad**

## Referencias

- IEEE 754-2008 Standard for Floating-Point Arithmetic
- Vivado Design Suite User Guide
- Basys3 FPGA Board Reference Manual
- Computer Arithmetic: Algorithms and Hardware Designs (Parhami)