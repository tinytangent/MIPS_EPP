library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.MIPSCPU.all;
use work.MIPSCP0.all;
use work.HardwareController.all;

entity Processor is
	port (
		reset : in Reset_t;
		clock : in Clock_t;
		debugData : out CPUDebugData_t;
		primaryRAMControl : out HardwareRAMControl_t;
		primaryRAMResult : in RAMData_t;
		secondaryRAMControl : out HardwareRAMControl_t;
		secondaryRAMResult : in RAMData_t;
		uart1Control : out HardwareRegisterControl_t;
		uart1Result : in CPUData_t
	);
end entity;

architecture Behavioral of Processor is
	signal register_file_input: std_logic_vector (MIPS_CPU_DATA_WIDTH - 1 downto 0);
	signal register_file_operation: std_logic_vector (MIPS_CPU_REGISTER_COUNT - 1 downto 0);
	signal register_file_output : mips_register_file_port;
	signal registerFileControl1 : RegisterFileControl_t;
	signal registerFileControl2 : RegisterFileControl_t;

	signal pipelinePhaseIDEXInterface : PipelinePhaseIDEXInterface_t;
	signal pipelinePhaseEXMAInterface : PipelinePhaseEXMAInterface_t;
	signal pipelinePhaseMAWBInterface : PipelinePhaseMAWBInterface_t;

	signal instructionToCP0 : Instruction_t;
	signal instructionToPrimary : Instruction_t;
	signal instructionExecutionEnabledCP0 : EnablingControl_t;
	signal instruction_done : std_logic;

	signal current_pipeline_phase : std_logic_vector(3 downto 0) := "0000";

	signal ramControl1 : RAMControl_t;
	signal ramControl2 : RAMControl_t;
	signal ramControl3 : RAMControl_t;
	signal memoryAccessResult : RAMData_t;

	signal pcControl1 : RegisterControl_t;
	signal pcControl2 : RegisterControl_t;
	signal pcControl3 : RegisterControl_t;
	signal pcValue : std_logic_vector(MIPS_CPU_DATA_WIDTH - 1 downto 0);
	
	signal cp0ExceptionPCOverrideControl : RegisterControl_t;
	signal cp0ExceptionPipelineClear : EnablingControl_t;
	signal cp0ExceptionTrigger : CP0ExceptionTrigger_t;

	component RegisterFile is
    Port (
		reset : in std_logic;
		clock : in std_logic;
		input : in std_logic_vector (MIPS_CPU_DATA_WIDTH - 1 downto 0);
		operation : in std_logic_vector (MIPS_CPU_REGISTER_COUNT - 1 downto 0);
		output : out mips_register_file_port
	);
	end component;

	component PipelinePhaseInstructionDecode is
	port (
		reset : in std_logic;
		clock : in std_logic;
		register_file : in mips_register_file_port;
		instruction : in std_logic_vector(MIPS_CPU_INSTRUCTION_WIDTH - 1 downto 0);
		phaseExCtrlOutput : out PipelinePhaseIDEXInterface_t;
		pcValue : in std_logic_vector (MIPS_CPU_DATA_WIDTH - 1 downto 0);
		pcControl : out RegisterControl_t
	);
	end component;

	component PipelinePhaseExecute is
	port (
		reset : in std_logic;
		clock : in std_logic;
		phaseIDInput : in PipelinePhaseIDEXInterface_t;
		pcValue : in std_logic_vector (MIPS_CPU_DATA_WIDTH - 1 downto 0);
		pcControl : out RegisterControl_t;
		phaseMACtrlOutput : out PipelinePhaseEXMAInterface_t
	);
	end component;

begin

	registerFile_i : RegisterFile port map (
		reset => reset,
		clock => clock,
		input => register_file_input,
		operation => register_file_operation,
		output => register_file_output
	);

	pcRegister_i : entity work.SpecialRegister port map (
		reset => reset,
		clock => clock,
		control0 => cp0ExceptionPCOverrideControl,
		control1 => pcControl1,
		control2 => pcControl2,
		control3 => pcControl3,
		output => pcValue
	);

	pipelinePhaseInstructionDecode_i: PipelinePhaseInstructionDecode port map (
		reset => reset,
		clock => clock,
		register_file => register_file_output,
		instruction => instructionToPrimary,
		phaseExCtrlOutput => pipelinePhaseIDEXInterface,
		pcValue => pcValue,
		pcControl => pcControl1
	);

	pipelinePhaseExecute_i: entity work.PipelinePhaseExecute
	port map (
		reset => reset,
		clock => clock,
		phaseIDInput => pipelinePhaseIDEXInterface,
		pcValue => pcValue,
		pcControl => pcControl3,
		ramControl => ramControl1,
		phaseMACtrlOutput => pipelinePhaseEXMAInterface
	);

	pipelinePhaseMemoryAccess_i: entity work.PipelinePhaseMemoryAccess
	port map (
		reset => reset,
		clock => clock,
		phaseEXInput => pipelinePhaseEXMAInterface,
		phaseWBCtrlOutput => pipelinePhaseMAWBInterface,
		exceptionTriggerOutput => cp0ExceptionTrigger,
		ramReadResult => memoryAccessResult
	);

	pipelinePhaseWirteBack_i: entity work.PipelinePhaseWriteBack
	port map (
		ramControl => ramControl2,
		registerFileControl => registerFileControl1,
		phaseMAInput => pipelinePhaseMAWBInterface
	);
	
	registerFileWriter_i: entity work.RegisterFileWriter
	port map
	(
		control1 => registerFileControl1,
		control2 => (
			address => (others => '0'),
			data => (others => '0')
		),
		operation_output => register_file_operation,
		data_output => register_file_input
	);

	Coprocessor0_i : entity work.Coprocessor0_e
	port map
	(
		reset => reset,
		clock => clock,
		instruction => instructionToCP0,
		instructionExecutionEnabled => instructionExecutionEnabledCP0,
		primaryRegisterFileData => register_file_output,
		primaryRegisterFileControl => registerFileControl2,
		pcValue => pcValue,
		pcControl => cp0ExceptionPCOverrideControl,
		exceptionTrigger => cp0ExceptionTrigger,
		exceptionPipelineClear => cp0ExceptionPipelineClear,
		debugCP0RegisterFileData => open
	);
	
	hardwareAddressMapper : entity work.HardwareAddressMapper
	port map
	(
		clock => clock,
		reset => reset,
		ramControl1 => ramControl1,
		ramControl2 => ramControl2,
		ramControl3 => ramControl3,
		result => memoryAccessResult,
		primaryRAMHardwareControl => primaryRAMControl,
		primaryRAMResult => primaryRAMResult,
		secondaryRAMHardwareControl => secondaryRAMControl,
		secondaryRAMResult => secondaryRAMResult,
		uart1Control => uart1Control,
		uart1Result => uart1Result
	);
	
	-- Output internal debug data.
	debugData <= (
		pcValue => pcValue,
		primaryRegisterFile => register_file_output,
		currentInstruction => instructionToPrimary
	);

	Processor_Process : process (clock, reset)
		variable opcode : InstructionOpcode_t;
		variable instruction : Instruction_t;
	begin
		if reset = '0' then
			instructionToPrimary <= MIPS_CPU_INSTRUCTION_NOP;
			instructionExecutionEnabledCP0 <= FUNC_DISABLED;
			--ramControl3.address <= (others => '0');
			--ramControl3.writeEnabled <= FUNC_DISABLED;
			--ramControl3.readEnabled <= FUNC_ENABLED;
			current_pipeline_phase <= "0100";
		elsif rising_edge(clock) then
			if cp0exceptionPipelineClear = FUNC_ENABLED then
				current_pipeline_phase <= "0100";
			else
				if current_pipeline_phase = "0000" then
					instruction := memoryAccessResult;
					opcode :=
						instruction(MIPS_CPU_INSTRUCTION_OPCODE_HI downto MIPS_CPU_INSTRUCTION_OPCODE_LO);
					if opcode = MIPS_CPU_INSTRUCTION_OPCODE_CP0 then
						instructionToPrimary <= MIPS_CPU_INSTRUCTION_NOP;
						instructionToCP0 <= instruction;
						instructionExecutionEnabledCP0 <= FUNC_ENABLED;
					else
						instructionToPrimary <= instruction;
						instructionToCP0 <= MIPS_CPU_INSTRUCTION_NOP;
						instructionExecutionEnabledCP0 <= FUNC_DISABLED;
					end if;
					pcControl2.operation <= REGISTER_OPERATION_READ;
					current_pipeline_phase <= current_pipeline_phase + 1;
					ramControl3.writeEnabled <= FUNC_DISABLED;
					ramControl3.readEnabled <= FUNC_DISABLED;
				elsif current_pipeline_phase = "0100" then
					pcControl2.operation <= REGISTER_OPERATION_WRITE;
					pcControl2.data <= pcValue + 4;
					current_pipeline_phase <= "0000";
					instructionToPrimary <= MIPS_CPU_INSTRUCTION_NOP;
					instructionExecutionEnabledCP0 <= FUNC_DISABLED;
					ramControl3.address <= pcValue;
					ramControl3.writeEnabled <= FUNC_DISABLED;
					ramControl3.readEnabled <= FUNC_ENABLED;
					ramControl3.data <= (others => '0');
				else
					pcControl2.operation <= REGISTER_OPERATION_READ;
					instructionToPrimary <= MIPS_CPU_INSTRUCTION_NOP;
					instructionExecutionEnabledCP0 <= FUNC_DISABLED;
					current_pipeline_phase <= current_pipeline_phase + 1;
					ramControl3.writeEnabled <= FUNC_DISABLED;
					ramControl3.readEnabled <= FUNC_DISABLED;
				end if;
			end if;
		end if;
	end process;
end architecture;
